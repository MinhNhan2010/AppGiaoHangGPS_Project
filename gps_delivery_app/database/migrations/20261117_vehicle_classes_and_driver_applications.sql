-- Additive migration: Vehicle classes (motorbike / ev_scooter / tricycle / van / 1.5t truck) for
-- quotes, orders and auto-dispatch capacity matching, plus the Driver Partner Application
-- (vehicle, licence and private identity documents) reviewed through partner memberships.
-- Safe to reapply; seeds no rows. Apply after 20261116_realtime_dispatch_pricing_and_pod_signature.sql.
begin;

-- ============================================================================
-- PART 1: VEHICLE CLASS HELPERS
-- ============================================================================

create or replace function public.delivery_vehicle_max_kg(p_vehicle text) returns integer
language sql immutable set search_path='' as $$
  select case p_vehicle
    when 'motorbike' then 30
    when 'ev_scooter' then 30
    when 'tricycle' then 300
    when 'van' then 500
    when 'truck' then 1500
    else null
  end;
$$;

revoke all on function public.delivery_vehicle_max_kg(text) from public, anon, authenticated;

-- Resolves the vehicle class of an order/quote details object (old orders have no vehicle_type).
create or replace function public.delivery_order_vehicle_type(p_details jsonb) returns text
language sql immutable set search_path='' as $$
  select case
    when jsonb_typeof(p_details->'vehicle_type') = 'string'
         and (p_details->>'vehicle_type') in ('motorbike','ev_scooter','tricycle','van','truck')
      then p_details->>'vehicle_type'
    when coalesce(p_details->>'service_type', 'standard') = 'truck' then 'van'
    when p_details->'prefer_ev' = 'true'::jsonb then 'ev_scooter'
    else 'motorbike'
  end;
$$;

revoke all on function public.delivery_order_vehicle_type(jsonb) from public, anon, authenticated;

-- Capacity rule: may a driver with vehicle p_driver serve an order that requires p_order?
create or replace function public.delivery_vehicle_can_serve(p_driver text, p_order text) returns boolean
language sql immutable set search_path='' as $$
  select coalesce(case p_order
    when 'motorbike' then p_driver in ('motorbike', 'ev_scooter')
    when 'ev_scooter' then p_driver = 'ev_scooter'
    when 'tricycle' then p_driver in ('tricycle', 'van', 'truck')
    when 'van' then p_driver in ('van', 'truck')
    when 'truck' then p_driver = 'truck'
    else false
  end, false);
$$;

revoke all on function public.delivery_vehicle_can_serve(text, text) from public, anon, authenticated;

-- Driver presence accepts the five vehicle ids (existing 'motorbike'/'ev_scooter'/'truck' rows stay valid).
do $$
declare c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.delivery_driver_presence'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%vehicle_type%'
  loop
    execute format('alter table public.delivery_driver_presence drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.delivery_driver_presence
  add constraint delivery_driver_presence_vehicle_type_check
  check (vehicle_type in ('motorbike', 'ev_scooter', 'tricycle', 'van', 'truck'));

-- ============================================================================
-- PART 2: DRIVER PARTNER APPLICATIONS (private, RPC-only)
-- ============================================================================

create table if not exists public.delivery_driver_applications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  vehicle_type text not null check (vehicle_type in ('motorbike', 'ev_scooter', 'tricycle', 'van', 'truck')),
  license_plate text not null check (char_length(license_plate) between 6 and 16),
  vehicle_brand text not null check (char_length(vehicle_brand) between 2 and 60),
  vehicle_color text not null check (char_length(vehicle_color) between 2 and 30),
  license_number text not null check (license_number ~ '^[0-9]{12}$'),
  license_class text not null check (license_class in ('A1', 'A', 'A2', 'B', 'B1', 'B2', 'C1', 'C')),
  operating_area text not null check (char_length(operating_area) between 2 and 120),
  documents jsonb not null default '{}'::jsonb check (jsonb_typeof(documents) = 'object'),
  state text not null default 'pending' check (state in ('pending', 'approved', 'rejected')),
  reason text not null default '' check (char_length(reason) <= 500),
  version integer not null default 1 check (version >= 1),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists delivery_driver_applications_admin_idx
  on public.delivery_driver_applications(state, submitted_at desc, user_id);

alter table public.delivery_driver_applications enable row level security;
revoke all on table public.delivery_driver_applications from public, anon, authenticated;

create or replace function public.delivery_driver_application_payload(p_app public.delivery_driver_applications) returns jsonb
language sql stable security definer set search_path='' as $$
  select case when p_app.user_id is null then null else jsonb_build_object(
    'vehicle_type', p_app.vehicle_type,
    'license_plate', p_app.license_plate,
    'vehicle_brand', p_app.vehicle_brand,
    'vehicle_color', p_app.vehicle_color,
    'license_number', p_app.license_number,
    'license_class', p_app.license_class,
    'operating_area', p_app.operating_area,
    'documents', p_app.documents,
    'state', p_app.state,
    'reason', p_app.reason,
    'submitted_at', p_app.submitted_at,
    'reviewed_at', p_app.reviewed_at,
    'version', p_app.version
  ) end;
$$;

revoke all on function public.delivery_driver_application_payload(public.delivery_driver_applications) from public, anon, authenticated;

-- Private identity documents live in delivery-private-evidence under driver-applications/<uid>/.
-- Uploads: only the owner, with a completed unblocked profile, while no application is pending/approved.
create or replace function public.delivery_driver_application_can_upload(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null
    and coalesce(p_name, '') ~ ('^driver-applications/' || auth.uid()::text
      || '/(citizen_front|citizen_back|license|vehicle_registration|portrait)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$')
    and exists (
      select 1 from public.delivery_cloud_accounts a
      where a.user_id = auth.uid() and not a.blocked
    )
    and not exists (
      select 1 from public.delivery_driver_applications ap
      where ap.user_id = auth.uid() and ap.state in ('pending', 'approved')
    );
$$;

-- Reads (signed URLs): operators, or the owner of the folder.
create or replace function public.delivery_driver_application_can_read(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce(p_name, '') like 'driver-applications/%'
    and (
      public.delivery_is_operator()
      or (auth.uid() is not null and split_part(p_name, '/', 2) = auth.uid()::text)
    );
$$;

revoke all on function public.delivery_driver_application_can_upload(text) from public, anon;
revoke all on function public.delivery_driver_application_can_read(text) from public, anon;
grant execute on function public.delivery_driver_application_can_upload(text) to authenticated;
grant execute on function public.delivery_driver_application_can_read(text) to authenticated;

drop policy if exists delivery_driver_application_docs_insert on storage.objects;
create policy delivery_driver_application_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'delivery-private-evidence' and public.delivery_driver_application_can_upload(name));

drop policy if exists delivery_driver_application_docs_select on storage.objects;
create policy delivery_driver_application_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'delivery-private-evidence' and public.delivery_driver_application_can_read(name));

-- ============================================================================
-- PART 3: QUOTE / ORDER CREATION / DRIVER QUEUE WITH VEHICLE CLASS
-- ============================================================================

-- Extends delivery_cloud_quote (20261116) with vehicle_type, max_weight_kg and breakdown.vehicle_fee.
create or replace function public.delivery_cloud_quote(p_details jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  p public.delivery_cloud_pricing;
  r public.delivery_cloud_pricing_rules;
  gz record;
  a float8; leg_m integer; meters integer := 0; fee integer;
  weight numeric; vol_weight numeric := 0; eff_weight numeric; max_weight numeric;
  lat1 float8; lat2 float8; lng1 float8; lng2 float8; cur_lat float8; cur_lng float8;
  wp jsonb; wp_lat float8; wp_lng float8; stop_count integer := 0;
  l_cm numeric := 0; w_cm numeric := 0; h_cm numeric := 0;
  declared_val numeric := 0; is_round boolean := false; prefer_ev boolean := false; green_fund boolean := false;
  use_coins boolean := false; wallet_bal bigint := 0; max_coin_disc integer := 0; coin_disc integer := 0; payable integer := 0;
  service text; v_base integer; v_dist integer; v_weight integer; v_express integer := 0;
  v_stop integer := 0; v_round integer := 0; v_ins integer := 0; v_green integer := 0; v_per_km integer;
  v_free_km numeric := 2.0;
  v_surge integer := 0;
  v_geofence integer := 0;
  v_zone_fee integer := 0;
  v_matched_zones jsonb := '[]'::jsonb;
  v_vehicle text;
  v_vehicle_max integer;
  v_vehicle_fee integer := 0;
begin
  if not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Cần hoàn thiện hồ sơ và tài khoản đang hoạt động.';
  end if;
  if jsonb_typeof(p_details) is distinct from 'object' or
     not (p_details ?& array['pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg','service_type']) or
     jsonb_typeof(p_details->'pickup_lat') <> 'number' or jsonb_typeof(p_details->'pickup_lng') <> 'number' or
     jsonb_typeof(p_details->'dropoff_lat') <> 'number' or jsonb_typeof(p_details->'dropoff_lng') <> 'number' or
     jsonb_typeof(p_details->'weight_kg') <> 'number' then
    raise sqlstate 'PT400' using message = 'Cần tọa độ và khối lượng hợp lệ.';
  end if;

  lat1 := (p_details->>'pickup_lat')::float8; lng1 := (p_details->>'pickup_lng')::float8;
  lat2 := (p_details->>'dropoff_lat')::float8; lng2 := (p_details->>'dropoff_lng')::float8;
  weight := (p_details->>'weight_kg')::numeric; service := p_details->>'service_type';
  if abs(lat1) > 90 or abs(lat2) > 90 or abs(lng1) > 180 or abs(lng2) > 180 or
     weight <= 0 or service is null or service not in ('standard','express','saving','same_day_2h','truck') then
    raise sqlstate 'PT400' using message = 'Tọa độ, dịch vụ hoặc khối lượng không hợp lệ.';
  end if;
  if p_details ? 'prefer_ev' then
    if jsonb_typeof(p_details->'prefer_ev') <> 'boolean' then
      raise sqlstate 'PT400' using message = 'Tùy chọn xe điện không hợp lệ.';
    end if;
    prefer_ev := (p_details->>'prefer_ev')::boolean;
  end if;

  -- Vehicle class: optional for old clients (truck service -> van, prefer_ev -> ev_scooter, else motorbike)
  if p_details ? 'vehicle_type' and (
       jsonb_typeof(p_details->'vehicle_type') is distinct from 'string' or
       (p_details->>'vehicle_type') not in ('motorbike','ev_scooter','tricycle','van','truck')) then
    raise sqlstate 'PT400' using message = 'Loại phương tiện không hợp lệ. Chọn Xe máy, Xe máy điện, Xe ba gác, Xe van hoặc Xe tải 1,5 tấn.';
  end if;
  v_vehicle := coalesce(p_details->>'vehicle_type',
    case when service = 'truck' then 'van' when prefer_ev then 'ev_scooter' else 'motorbike' end);
  if (v_vehicle in ('motorbike','ev_scooter') and service = 'truck') or
     (v_vehicle in ('tricycle','van','truck') and service <> 'truck') then
    raise sqlstate 'PT400' using message = 'Phương tiện đã chọn không hỗ trợ dịch vụ này.';
  end if;
  if v_vehicle = 'ev_scooter' then prefer_ev := true; end if;
  v_vehicle_max := public.delivery_vehicle_max_kg(v_vehicle);
  max_weight := v_vehicle_max;
  if weight > max_weight then
    raise sqlstate 'PT400' using message = 'Khối lượng vượt tải trọng tối đa ' || v_vehicle_max || ' kg của phương tiện đã chọn.';
  end if;

  if p_details ? 'length_cm' or p_details ? 'width_cm' or p_details ? 'height_cm' then
    if jsonb_typeof(coalesce(p_details->'length_cm','0'::jsonb)) <> 'number' or
       jsonb_typeof(coalesce(p_details->'width_cm','0'::jsonb)) <> 'number' or
       jsonb_typeof(coalesce(p_details->'height_cm','0'::jsonb)) <> 'number' then
      raise sqlstate 'PT400' using message = 'Kích thước kiện hàng không hợp lệ.';
    end if;
    l_cm := coalesce((p_details->>'length_cm')::numeric, 0);
    w_cm := coalesce((p_details->>'width_cm')::numeric, 0);
    h_cm := coalesce((p_details->>'height_cm')::numeric, 0);
    if l_cm < 0 or w_cm < 0 or h_cm < 0 or l_cm > 300 or w_cm > 300 or h_cm > 300 then
      raise sqlstate 'PT400' using message = 'Kích thước mỗi chiều tối đa 300 cm.';
    end if;
    if l_cm > 0 and w_cm > 0 and h_cm > 0 then vol_weight := round((l_cm * w_cm * h_cm) / 5000.0, 2); end if;
  end if;
  eff_weight := greatest(weight, vol_weight);
  if eff_weight > max_weight then
    raise sqlstate 'PT400' using message = 'Khối lượng quy đổi theo kích thước vượt tải trọng tối đa ' || v_vehicle_max || ' kg của phương tiện đã chọn.';
  end if;

  cur_lat := lat1; cur_lng := lng1;
  if p_details ? 'extra_stops' then
    if jsonb_typeof(p_details->'extra_stops') <> 'array' or jsonb_array_length(p_details->'extra_stops') > 5 then
      raise sqlstate 'PT400' using message = 'Hỗ trợ tối đa 5 điểm dừng phụ.';
    end if;
    for wp in select * from jsonb_array_elements(p_details->'extra_stops') loop
      if jsonb_typeof(wp) <> 'object' or jsonb_typeof(wp->'lat') <> 'number' or jsonb_typeof(wp->'lng') <> 'number' or
         length(btrim(coalesce(wp->>'address',''))) not between 3 and 300 then
        raise sqlstate 'PT400' using message = 'Điểm dừng phụ không hợp lệ.';
      end if;
      wp_lat := (wp->>'lat')::float8; wp_lng := (wp->>'lng')::float8;
      if abs(wp_lat) > 90 or abs(wp_lng) > 180 then raise sqlstate 'PT400' using message = 'Tọa độ điểm dừng không hợp lệ.'; end if;
      a := power(sin(radians(wp_lat - cur_lat) / 2), 2) + cos(radians(cur_lat)) * cos(radians(wp_lat)) * power(sin(radians(wp_lng - cur_lng) / 2), 2);
      leg_m := ceil(6371000 * 2 * asin(sqrt(least(1, a))) * 1.3)::integer;
      meters := meters + leg_m; cur_lat := wp_lat; cur_lng := wp_lng; stop_count := stop_count + 1;
    end loop;
  end if;
  a := power(sin(radians(lat2 - cur_lat) / 2), 2) + cos(radians(cur_lat)) * cos(radians(lat2)) * power(sin(radians(lng2 - cur_lng) / 2), 2);
  meters := greatest(1, meters + ceil(6371000 * 2 * asin(sqrt(least(1, a))) * 1.3)::integer);
  if meters > 200000 then raise sqlstate 'PT400' using message = 'Ngoài phạm vi giao hàng 200 km.'; end if;
  if service = 'same_day_2h' and meters > 50000 then raise sqlstate 'PT400' using message = 'Giao nhanh 2H chỉ áp dụng trong bán kính 50 km nội thành.'; end if;

  if p_details ? 'declared_value' then
    if jsonb_typeof(p_details->'declared_value') <> 'number' or (p_details->>'declared_value')::numeric not between 0 and 30000000 or
       (p_details->>'declared_value')::numeric <> trunc((p_details->>'declared_value')::numeric) then
      raise sqlstate 'PT400' using message = 'Giá trị khai giá tối đa 30.000.000 đ.';
    end if;
    declared_val := (p_details->>'declared_value')::numeric;
  end if;
  if p_details ? 'is_round_trip' then
    if jsonb_typeof(p_details->'is_round_trip') <> 'boolean' then raise sqlstate 'PT400' using message = 'Tùy chọn khứ hồi không hợp lệ.'; end if;
    is_round := (p_details->>'is_round_trip')::boolean;
  end if;
  if p_details ? 'green_fund' then
    if jsonb_typeof(p_details->'green_fund') <> 'boolean' then raise sqlstate 'PT400' using message = 'Tùy chọn quỹ xanh không hợp lệ.'; end if;
    green_fund := (p_details->>'green_fund')::boolean;
  end if;
  if p_details ? 'use_coins' then
    if jsonb_typeof(p_details->'use_coins') <> 'boolean' then raise sqlstate 'PT400' using message = 'Tùy chọn dùng Xu không hợp lệ.'; end if;
    use_coins := (p_details->>'use_coins')::boolean;
  end if;
  if p_details ? 'require_signature' and jsonb_typeof(p_details->'require_signature') <> 'boolean' then
    raise sqlstate 'PT400' using message = 'Tùy chọn chữ ký người nhận không hợp lệ.';
  end if;
  if p_details ? 'scheduled_at' and p_details->'scheduled_at' is not null and jsonb_typeof(p_details->'scheduled_at') <> 'null' then
    if jsonb_typeof(p_details->'scheduled_at') <> 'string' or (p_details->>'scheduled_at')::timestamptz < now() + interval '10 minutes' or
       (p_details->>'scheduled_at')::timestamptz > now() + interval '7 days' then
      raise sqlstate 'PT400' using message = 'Lịch hẹn lấy hàng cần từ 10 phút tới 7 ngày.';
    end if;
  end if;

  select * into p from public.delivery_cloud_pricing where id;
  select * into r from public.delivery_cloud_pricing_rules where service_type = service and active;

  if found then
    v_base := r.base_fee;
    v_per_km := r.per_km;
    v_free_km := r.free_km;
    v_weight := greatest(0, ceil(eff_weight - r.free_weight_kg))::integer * r.extra_kg;
    v_express := 0;
    v_dist := greatest(0, ceil(meters / 1000.0 - v_free_km))::integer * v_per_km;
    if r.peak_enabled and r.peak_multiplier_bps > 10000 then
      v_surge := v_surge + round((v_base + v_dist) * ((r.peak_multiplier_bps - 10000)::numeric / 10000.0))::integer;
    end if;
    if r.weather_enabled and r.weather_surcharge > 0 then
      v_surge := v_surge + r.weather_surcharge;
    end if;
  else
    if service in ('standard','express') then
      v_base := p.base_fee; v_per_km := p.per_km;
      v_weight := greatest(0, ceil(eff_weight - 5))::integer * p.extra_kg;
      v_express := case when service = 'express' then p.express_fee else 0 end;
    elsif service = 'saving' then
      v_base := greatest(12000, round(p.base_fee * 0.48)::integer);
      v_per_km := greatest(4000, round(p.per_km * 0.80)::integer);
      v_weight := greatest(0, ceil(eff_weight - 5))::integer * p.extra_kg;
    elsif service = 'same_day_2h' then
      v_base := greatest(12000, round(p.base_fee * 0.48)::integer);
      v_per_km := greatest(5500, round(p.per_km * 1.10)::integer);
      v_weight := greatest(0, ceil(eff_weight - 5))::integer * p.extra_kg;
    else
      v_base := greatest(80000, p.base_fee * 3 + 5000);
      v_per_km := p.per_km * 3;
      v_weight := greatest(0, ceil(eff_weight - 20))::integer * p.extra_kg;
    end if;
    v_dist := greatest(0, ceil(meters / 1000.0) - 2)::integer * v_per_km;
  end if;

  -- Evaluate active polygon geofences on pickup or dropoff coordinates
  for gz in
    select id, name, zone_type, surcharge_fee, multiplier_bps, polygon
    from public.delivery_cloud_geofences
    where active
    order by updated_at desc, id desc
  loop
    if public.delivery_point_in_polygon(lat1, lng1, gz.polygon)
       or public.delivery_point_in_polygon(lat2, lng2, gz.polygon) then
      v_zone_fee := gz.surcharge_fee
        + case
            when gz.multiplier_bps > 10000
              then round((v_base + v_dist) * ((gz.multiplier_bps - 10000)::numeric / 10000.0))::integer
            else 0
          end;
      v_geofence := v_geofence + greatest(0, v_zone_fee);
      v_matched_zones := v_matched_zones || jsonb_build_array(gz.name);
    end if;
  end loop;

  v_stop := stop_count * 5000;
  v_round := case when is_round then round((v_base + v_dist) * 0.60)::integer else 0 end;
  v_ins := case when declared_val > 0 then least(150000, greatest(2000, round(declared_val * 0.005)::integer)) else 0 end;
  v_green := case when green_fund then 1000 else 0 end;
  v_vehicle_fee := case v_vehicle
    when 'van' then 60000 + 3000 * greatest(0, ceil(meters / 1000.0 - 2))::integer
    when 'truck' then 150000 + 8000 * greatest(0, ceil(meters / 1000.0 - 2))::integer
    else 0
  end;
  fee := v_base + v_dist + v_weight + v_express + v_stop + v_round + v_ins + v_green + v_surge + v_geofence + v_vehicle_fee;

  select coalesce(balance, 0) into wallet_bal
    from public.delivery_market_coin_wallets
    where user_id = auth.uid();
  max_coin_disc := least(wallet_bal, floor(fee * 0.20)::bigint, greatest(0, fee - 1000))::integer;
  coin_disc := case when use_coins then max_coin_disc else 0 end;
  payable := greatest(0, fee - coin_disc);

  return jsonb_build_object(
    'shipping_fee', fee,
    'coin_discount', coin_disc,
    'payable_fee', payable,
    'available_coins', wallet_bal,
    'max_coin_discount', max_coin_disc,
    'distance_meters', meters,
    'pricing_version', p.version,
    'distance_source', 'geodesic_estimate',
    'currency', 'VND',
    'service_type', service,
    'vehicle_type', v_vehicle,
    'max_weight_kg', v_vehicle_max,
    'effective_weight_kg', eff_weight,
    'volumetric_weight_kg', vol_weight,
    'stop_count', stop_count,
    'estimated_co2_saved_grams', case when prefer_ev then round((meters / 1000.0) * 48.0)::integer else 0 end,
    'breakdown', jsonb_build_object(
      'base_fee', v_base,
      'distance_fee', v_dist,
      'weight_fee', v_weight,
      'express_fee', v_express
    ) || case when v_stop > 0 then jsonb_build_object('stop_fee', v_stop) else '{}'::jsonb end
      || case when v_round > 0 then jsonb_build_object('round_trip_fee', v_round) else '{}'::jsonb end
      || case when v_ins > 0 then jsonb_build_object('insurance_fee', v_ins) else '{}'::jsonb end
      || case when v_green > 0 then jsonb_build_object('green_fee', v_green) else '{}'::jsonb end
      || case when v_surge > 0 then jsonb_build_object('surge_fee', v_surge) else '{}'::jsonb end
      || case when v_geofence > 0 then jsonb_build_object('geofence_fee', v_geofence) else '{}'::jsonb end
      || case when v_vehicle_fee > 0 then jsonb_build_object('vehicle_fee', v_vehicle_fee) else '{}'::jsonb end
  ) || case
    when jsonb_array_length(v_matched_zones) > 0
      then jsonb_build_object('matched_geofences', v_matched_zones)
    else '{}'::jsonb
  end;
end; $$;

revoke all on function public.delivery_cloud_quote(jsonb) from public, anon;
grant execute on function public.delivery_cloud_quote(jsonb) to authenticated;

-- Extends delivery_cloud_create (20261116): accepts vehicle_type and stores the resolved class in details.
create or replace function public.delivery_cloud_create(
  p_details jsonb,
  p_request_key uuid,
  p_pricing_version integer,
  p_expected_fee integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  a public.delivery_cloud_accounts;
  q jsonb;
  merchant uuid;
  saved jsonb;
  raw_bytes bytea;
  otp_val text;
  v_coin_disc integer := 0;
  v_payable integer := 0;
  v_details jsonb;
begin
  if not public.delivery_cloud_active() then raise sqlstate 'PT403' using message = 'Cần hồ sơ đang hoạt động.'; end if;
  if p_request_key is null then raise sqlstate 'PT400' using message = 'Thiếu mã yêu cầu.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_key::text, 0));
  saved := jsonb_build_object('details', p_details, 'pricing_version', p_pricing_version, 'expected_fee', p_expected_fee);
  select * into o from public.delivery_cloud_orders where owner_id = auth.uid() and request_key = p_request_key;
  if found then
    if o.request_payload <> saved then raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.'; end if;
    return to_jsonb(o) - 'request_payload' - 'request_key';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id = auth.uid();
  if octet_length(p_details::text) > 12000 or p_details - array[
    'pickup_address','dropoff_address','recipient_name','recipient_phone','package_description',
    'pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg','cod_amount','service_type',
    'payment_method','merchant_id','length_cm','width_cm','height_cm','declared_value','extra_stops',
    'is_round_trip','prefer_ev','green_fund','scheduled_at','buyer_note','require_pod','require_otp',
    'require_signature','use_coins','vehicle_type'
  ] <> '{}'::jsonb then
    raise sqlstate 'PT400' using message = 'Đơn hàng có trường không hỗ trợ hoặc quá dài.';
  end if;

  if coalesce((p_details->>'use_coins')::boolean, false) then
    perform 1 from public.delivery_market_coin_wallets where user_id = auth.uid() for update;
  end if;

  q := public.delivery_cloud_quote(p_details);
  v_coin_disc := coalesce((q->>'coin_discount')::integer, 0);
  v_payable := coalesce((q->>'payable_fee')::integer, (q->>'shipping_fee')::integer);
  -- Persist the server-resolved vehicle class so list/detail payloads expose details.vehicle_type
  v_details := p_details || jsonb_build_object('vehicle_type', q->>'vehicle_type')
    || case when q->>'vehicle_type' = 'ev_scooter' then jsonb_build_object('prefer_ev', true) else '{}'::jsonb end;

  if p_pricing_version is distinct from (q->>'pricing_version')::integer
     or p_expected_fee is distinct from v_payable then
    raise sqlstate 'PT409' using message = 'Giá cước hoặc số dư Xu đã thay đổi. Vui lòng lấy báo giá lại.';
  end if;

  if length(btrim(coalesce(p_details->>'pickup_address',''))) not between 5 and 500 or
     length(btrim(coalesce(p_details->>'dropoff_address',''))) not between 5 and 500 or
     length(btrim(coalesce(p_details->>'recipient_name',''))) not between 1 and 120 or
     coalesce(p_details->>'recipient_phone','') !~ '^0[35789][0-9]{8}$' or
     length(btrim(coalesce(p_details->>'package_description',''))) not between 1 and 1000 or
     length(coalesce(p_details->>'buyer_note','')) > 500 or
     (p_details ? 'require_pod' and jsonb_typeof(p_details->'require_pod') <> 'boolean') or
     (p_details ? 'require_otp' and jsonb_typeof(p_details->'require_otp') <> 'boolean') or
     (p_details ? 'require_signature' and jsonb_typeof(p_details->'require_signature') <> 'boolean') or
     jsonb_typeof(p_details->'cod_amount') is distinct from 'number' or
     (p_details->>'cod_amount')::numeric not between 0 and 20000000 or
     trunc((p_details->>'cod_amount')::numeric) <> (p_details->>'cod_amount')::numeric or
     coalesce(p_details->>'payment_method','') not in ('sender_cash','recipient_cash') then
    raise sqlstate 'PT400' using message = 'Thông tin người nhận, hàng hóa, COD hoặc phương thức trả phí không hợp lệ.';
  end if;
  merchant := case when public.delivery_cloud_has_membership(a.user_id, 'merchant') then auth.uid() else nullif(p_details->>'merchant_id','')::uuid end;
  if merchant is not null and not exists(select 1 from public.delivery_cloud_accounts where user_id = merchant and public.delivery_cloud_has_membership(user_id, 'merchant') and not blocked) then
    raise sqlstate 'PT400' using message = 'Cửa hàng chưa được duyệt hoặc đang khóa.';
  end if;

  insert into public.delivery_cloud_orders(
    owner_id, merchant_id, request_key, request_payload, details, distance_meters,
    shipping_fee, coin_discount, payable_fee, cod_amount, pricing_version, merchant_ready
  ) values (
    auth.uid(), merchant, p_request_key, saved, v_details, (q->>'distance_meters')::integer,
    (q->>'shipping_fee')::integer, v_coin_disc, v_payable,
    (p_details->>'cod_amount')::integer, (q->>'pricing_version')::integer, merchant is null
  ) returning * into o;

  if v_coin_disc > 0 then
    update public.delivery_market_coin_wallets
      set balance = balance - v_coin_disc, updated_at = now()
      where user_id = auth.uid() and balance >= v_coin_disc;
    if not found then
      raise sqlstate 'PT409' using message = 'Số dư Xu không đủ để giảm cước phí.';
    end if;
    insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
      values (auth.uid(), -v_coin_disc, 'redeem_shipping', o.id);
  end if;

  if coalesce((p_details->>'require_otp')::boolean, false) then
    raw_bytes := sha256(convert_to(gen_random_uuid()::text || ':' || o.id::text, 'UTF8'));
    otp_val := ((get_byte(raw_bytes, 0) * 65536 + get_byte(raw_bytes, 1) * 256 + get_byte(raw_bytes, 2)) % 900000 + 100000)::text;
    insert into public.delivery_cloud_order_secrets(order_id, otp_code, otp_hash)
      values (o.id, otp_val, encode(sha256(convert_to(otp_val, 'UTF8')), 'hex'));
  end if;
  insert into public.delivery_live_rooms(id) values (o.tracking_code);
  insert into public.delivery_live_members values (o.tracking_code, auth.uid(), case when public.delivery_cloud_has_membership(a.user_id, 'merchant') then 'merchant' else 'customer' end);
  if merchant is not null and merchant <> auth.uid() then insert into public.delivery_live_members values (o.tracking_code, merchant, 'merchant'); end if;
  insert into public.delivery_cloud_history(order_id, actor_id, action, status, version) values (o.id, auth.uid(), 'create', o.status, o.version);
  insert into public.delivery_live_events(room_id, kind, payload) values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));
  return to_jsonb(o) - 'request_payload' - 'request_key';
end; $$;

revoke all on function public.delivery_cloud_create(jsonb, uuid, integer, integer) from public, anon;
grant execute on function public.delivery_cloud_create(jsonb, uuid, integer, integer) to authenticated;

-- Extends delivery_cloud_list (20261116): driver queue exposes details.vehicle_type.
create or replace function public.delivery_cloud_list(
  p_queue boolean default false,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  a public.delivery_cloud_accounts;
  result jsonb;
begin
  select * into a from public.delivery_cloud_accounts where user_id = auth.uid();
  if not public.delivery_is_operator() and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Cần hồ sơ đang hoạt động.';
  end if;

  if p_queue then
    if not public.delivery_cloud_has_membership(a.user_id, 'driver') or a.blocked then
      raise sqlstate 'PT403' using message = 'Cần tài khoản tài xế được duyệt.';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'tracking_code', o.tracking_code,
      'shipping_fee', o.shipping_fee,
      'payable_fee', o.payable_fee,
      'estimated_earning', round(greatest(0, o.shipping_fee) * 0.80)::bigint,
      'coin_discount', o.coin_discount,
      'payment_status', o.payment_status,
      'cod_amount', o.cod_amount,
      'version', o.version,
      'status', o.status,
      'created_at', o.created_at,
      'distance_meters', o.distance_meters,
      'details', jsonb_build_object(
        'weight_kg', o.details->'weight_kg',
        'service_type', coalesce(o.details->'service_type', '"standard"'::jsonb),
        'vehicle_type', public.delivery_order_vehicle_type(o.details),
        'payment_method', coalesce(o.details->'payment_method', '"sender_cash"'::jsonb),
        'stops_count', case
          when jsonb_typeof(o.details->'extra_stops') = 'array' then jsonb_array_length(o.details->'extra_stops')
          else 0
        end,
        'is_round_trip', coalesce((o.details->>'is_round_trip')::boolean, false),
        'scheduled_at', o.details->'scheduled_at',
        'prefer_ev', coalesce((o.details->>'prefer_ev')::boolean, false),
        'require_pod', coalesce((o.details->>'require_pod')::boolean, false),
        'require_otp', coalesce((o.details->>'require_otp')::boolean, false),
        'require_signature', coalesce((o.details->>'require_signature')::boolean, false),
        'pickup_area', public.delivery_coarse_area(o.details->>'pickup_address'),
        'dropoff_area', public.delivery_coarse_area(o.details->>'dropoff_address'),
        'approx_pickup_lat', case
          when jsonb_typeof(o.details->'pickup_lat') = 'number' then round((o.details->>'pickup_lat')::numeric, 2)
          else null
        end,
        'approx_pickup_lng', case
          when jsonb_typeof(o.details->'pickup_lng') = 'number' then round((o.details->>'pickup_lng')::numeric, 2)
          else null
        end,
        'approx_dropoff_lat', case
          when jsonb_typeof(o.details->'dropoff_lat') = 'number' then round((o.details->>'dropoff_lat')::numeric, 2)
          else null
        end,
        'approx_dropoff_lng', case
          when jsonb_typeof(o.details->'dropoff_lng') = 'number' then round((o.details->>'dropoff_lng')::numeric, 2)
          else null
        end
      )
    ) order by o.created_at desc, o.id desc), '[]'::jsonb)
    into result
    from (
      select * from public.delivery_cloud_orders
      where status = 'searching'
        and merchant_ready
        and driver_id is null
        and fulfillment_provider is null
        and (
          p_before is null
          or (p_before_id is null and created_at < p_before)
          or (created_at, id) < (p_before, p_before_id)
        )
      order by created_at desc, id desc
      limit 50
    ) o;
  else
    select coalesce(
      jsonb_agg(public.delivery_cloud_order_enriched(o) order by o.created_at desc, o.id desc),
      '[]'::jsonb
    )
    into result
    from (
      select * from public.delivery_cloud_orders
      where (public.delivery_is_operator() or auth.uid() in (owner_id, merchant_id, driver_id))
        and (
          p_before is null
          or (p_before_id is null and created_at < p_before)
          or (created_at, id) < (p_before, p_before_id)
        )
      order by created_at desc, id desc
      limit 50
    ) o;
  end if;

  return jsonb_build_object('orders', result, 'page_size', 50);
end; $$;

revoke all on function public.delivery_cloud_list(boolean, timestamptz, uuid) from public, anon;
grant execute on function public.delivery_cloud_list(boolean, timestamptz, uuid) to authenticated;

-- ============================================================================
-- PART 4: DISPATCH CAPACITY MATCHING & APPROVED VEHICLE PINNING
-- ============================================================================

-- Proximity matcher (20261116) now applies the vehicle capacity rule.
create or replace function public.delivery_match_driver_offer_for_order(p_order_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  v_existing uuid;
  v_pickup_lat double precision;
  v_pickup_lng double precision;
  v_service text;
  v_prefer_ev boolean;
  v_order_vehicle text;
  v_tier integer;
  cand record;
  v_offer_id uuid;
  v_earning bigint;
begin
  if p_order_id is null then return null; end if;

  -- Expire stale pending offers globally first
  update public.delivery_driver_offers
    set state = 'expired', responded_at = coalesce(responded_at, now())
    where state = 'pending' and expires_at <= now();

  select * into o from public.delivery_cloud_orders where id = p_order_id;
  if not found
     or o.status <> 'searching'
     or not o.merchant_ready
     or o.driver_id is not null
     or o.fulfillment_provider is not null
     or jsonb_typeof(o.details->'pickup_lat') <> 'number'
     or jsonb_typeof(o.details->'pickup_lng') <> 'number' then
    return null;
  end if;

  if exists (
    select 1 from public.delivery_payment_transactions
    where order_id = o.id and status in ('CREATING', 'PENDING', 'REVIEW')
  ) then
    return null;
  end if;

  select id into v_existing
    from public.delivery_driver_offers
    where order_id = o.id and state = 'pending' and expires_at > now()
    order by created_at desc
    limit 1;
  if v_existing is not null then
    return v_existing;
  end if;

  v_pickup_lat := (o.details->>'pickup_lat')::double precision;
  v_pickup_lng := (o.details->>'pickup_lng')::double precision;
  v_service := coalesce(o.details->>'service_type', 'standard');
  v_prefer_ev := coalesce((o.details->>'prefer_ev')::boolean, false);
  v_order_vehicle := public.delivery_order_vehicle_type(o.details);
  v_earning := round(greatest(0, o.shipping_fee) * 0.80)::bigint;

  foreach v_tier in array array[3, 5, 8] loop
    select
      dp.user_id,
      dist_m,
      round(
        greatest(0.0, 100.0 - (dist_m / 80.0))
        + coalesce(rt.avg_rating, 4.8) * 6.0
        + case when v_prefer_ev and dp.vehicle_type = 'ev_scooter' then 12.0 else 0.0 end
        + case when coalesce(dw.balance, 0) >= 0 then 5.0 else -15.0 end
      , 2) as match_score
    into cand
    from public.delivery_driver_presence dp
    join public.delivery_cloud_accounts da on da.user_id = dp.user_id and not da.blocked
    left join public.delivery_driver_wallets dw on dw.user_id = dp.user_id
    left join lateral (
      select avg(pr.rating)::numeric as avg_rating
      from public.delivery_partner_reviews pr
      where pr.target_kind = 'driver' and pr.driver_id = dp.user_id and not pr.hidden
    ) rt on true
    cross join lateral (
      select public.delivery_haversine_meters(dp.latitude, dp.longitude, v_pickup_lat, v_pickup_lng) as dist_m
    ) geo
    where dp.is_online
      and dp.last_seen_at >= now() - interval '20 minutes'
      and dp.user_id <> o.owner_id
      and (o.merchant_id is null or dp.user_id <> o.merchant_id)
      and public.delivery_cloud_has_membership(dp.user_id, 'driver')
      and public.delivery_vehicle_can_serve(dp.vehicle_type, v_order_vehicle)
      and geo.dist_m <= v_tier * 1000
      and not exists (
        select 1 from public.delivery_cloud_orders active_o
        where active_o.driver_id = dp.user_id
          and active_o.status not in ('delivered', 'returned', 'cancelled')
      )
      and not exists (
        select 1 from public.delivery_driver_offers cur_off
        where cur_off.driver_id = dp.user_id
          and cur_off.state = 'pending'
          and cur_off.expires_at > now()
      )
      and not exists (
        select 1 from public.delivery_driver_offers prev_off
        where prev_off.order_id = o.id
          and prev_off.driver_id = dp.user_id
          and prev_off.state in ('rejected', 'expired')
          and prev_off.created_at >= now() - interval '10 minutes'
      )
    order by match_score desc, geo.dist_m asc, dp.updated_at asc
    limit 1;

    if cand.user_id is not null then
      insert into public.delivery_driver_offers(
        order_id, driver_id, state, distance_meters, radius_tier_km,
        estimated_earning, score, expires_at
      ) values (
        o.id, cand.user_id, 'pending', cand.dist_m, v_tier,
        v_earning, cand.match_score, now() + interval '28 seconds'
      ) returning id into v_offer_id;

      perform public.delivery_emit_notification(
        cand.user_id,
        'shipping',
        'driver_offer',
        'Cuốc mới cách ' || round((cand.dist_m / 1000.0)::numeric, 1) || ' km · 28s nhận ngay',
        'Thu nhập dự kiến +' || v_earning || ' đ · Mã đơn ' || o.tracking_code,
        'cloud_order',
        o.id,
        jsonb_build_object(
          'offer_id', v_offer_id,
          'tracking_code', o.tracking_code,
          'distance_meters', cand.dist_m,
          'estimated_earning', v_earning,
          'radius_tier_km', v_tier
        )
      );
      return v_offer_id;
    end if;
  end loop;

  return null;
end; $$;

revoke all on function public.delivery_match_driver_offer_for_order(uuid) from public, anon, authenticated;

-- Partner membership decisions (20261109) now sync the driver partner application.
create or replace function public.delivery_cloud_membership(p_role text,p_decision text,p_user uuid default null,
  p_version integer default null,p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_user,auth.uid()); a public.delivery_cloud_accounts; previous public.delivery_cloud_memberships;
  changed public.delivery_cloud_memberships; next_state text;
  app public.delivery_driver_applications; v_app_pending boolean:=false;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if p_role is null or p_role not in ('merchant','driver') or p_decision is null or
    p_decision not in ('request','grant','approve','reject','revoke') or p_reason is null or length(p_reason)>500 then
    raise sqlstate 'PT400' using message='Yêu cầu tư cách đối tác không hợp lệ.';
  end if;
  if p_decision='request' then
    if target<>auth.uid() then raise sqlstate 'PT403' using message='Chỉ được đăng ký cho chính mình.'; end if;
  elsif not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền quản trị.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('driver:'||target::text,0));
  select * into a from public.delivery_cloud_accounts where user_id=target for update;
  if not found then raise sqlstate 'PT404' using message='Cần hoàn thiện hồ sơ trước.'; end if;
  if a.blocked then raise sqlstate 'PT403' using message='Tài khoản đang khóa.'; end if;
  select * into previous from public.delivery_cloud_memberships where user_id=target and role=p_role for update;
  if p_role='driver' then
    v_app_pending:=exists(select 1 from public.delivery_driver_applications where user_id=target and state='pending');
  end if;
  if p_decision='request' then
    if previous.state in ('active','pending') then return jsonb_build_object('membership',to_jsonb(previous)-'user_id'-'reviewed_by'); end if;
    insert into public.delivery_cloud_memberships(user_id,role,state) values(target,p_role,'pending')
      on conflict(user_id,role) do update set state='pending',version=delivery_cloud_memberships.version+1,
        requested_at=now(),reviewed_at=null,reviewed_by=null,reason=''
      returning * into changed;
  elsif p_decision='grant' then
    if previous.user_id is null then
      if coalesce(p_version,0)<>0 then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
      insert into public.delivery_cloud_memberships(user_id,role,state,version,reviewed_at,reviewed_by,reason)
        values(target,p_role,'active',1,now(),auth.uid(),btrim(p_reason))
        returning * into changed;
    else
      if p_version is distinct from previous.version then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
      if previous.state='active' then raise sqlstate 'PT409' using message='Tài khoản đã được cấp quyền đối tác này.'; end if;
      update public.delivery_cloud_memberships
        set state='active',version=version+1,reviewed_at=now(),reviewed_by=auth.uid(),reason=btrim(p_reason)
        where user_id=target and role=p_role returning * into changed;
    end if;
    if a.role='customer' then
      update public.delivery_cloud_accounts set role=p_role where user_id=target;
    end if;
  else
    if previous.user_id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu đối tác.'; end if;
    if p_version is distinct from previous.version then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
    -- An already-active driver who submits a partner application can still have it approved.
    if (p_decision='approve' and previous.state<>'pending' and not (p_role='driver' and previous.state='active' and v_app_pending)) or
      (p_decision='reject' and previous.state<>'pending') or
      (p_decision='revoke' and previous.state<>'active') then
      raise sqlstate 'PT409' using message='Quyết định không phù hợp trạng thái hiện tại.';
    end if;
    if p_decision in ('reject','revoke') and length(btrim(p_reason))<3 then
      raise sqlstate 'PT400' using message='Cần lý do ít nhất 3 ký tự.';
    end if;
    if p_decision='revoke' and p_role='driver' and exists(select 1 from public.delivery_cloud_orders
      where driver_id=target and status not in ('delivered','returned','cancelled')) then
      raise sqlstate 'PT409' using message='Tài xế còn chuyến chưa hoàn tất.';
    end if;
    if p_decision='revoke' and p_role='merchant' and exists(select 1 from public.delivery_market_shop_orders o
      left join public.delivery_cloud_orders d on d.id=o.delivery_id where o.merchant_id=target and o.state<>'cancelled'
        and (d.id is null or d.status not in ('delivered','returned','cancelled'))) then
      raise sqlstate 'PT409' using message='Cửa hàng còn đơn chưa hoàn tất.';
    end if;
    next_state:=case p_decision when 'approve' then 'active' when 'reject' then 'rejected' else 'revoked' end;
    update public.delivery_cloud_memberships set state=next_state,version=version+1,reviewed_at=now(),reviewed_by=auth.uid(),reason=btrim(p_reason)
      where user_id=target and role=p_role returning * into changed;
    if p_decision='approve' and a.role='customer' then
      update public.delivery_cloud_accounts set role=p_role where user_id=target;
    elsif p_decision='revoke' and a.role=p_role then
      update public.delivery_cloud_accounts set role=coalesce((select role from public.delivery_cloud_memberships
        where user_id=target and state='active' order by role limit 1),'customer') where user_id=target;
    end if;
  end if;
  -- Keep the driver partner application in sync with the membership decision.
  if p_role='driver' then
    if p_decision in ('approve','grant') then
      update public.delivery_driver_applications
        set state='approved',reason=btrim(p_reason),reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now()
        where user_id=target and state='pending' returning * into app;
      if found then
        insert into public.delivery_driver_presence(user_id,vehicle_type) values(target,app.vehicle_type)
          on conflict(user_id) do update set vehicle_type=excluded.vehicle_type,updated_at=now();
      end if;
    elsif p_decision in ('reject','revoke') then
      update public.delivery_driver_applications
        set state='rejected',reason=btrim(p_reason),reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now()
        where user_id=target and state in ('pending','approved');
    end if;
  end if;
  update public.delivery_cloud_accounts set requested_role=(select role from public.delivery_cloud_memberships
    where user_id=target and state='pending' order by role limit 1),updated_at=now() where user_id=target;
  insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
    values(auth.uid(),'membership_'||p_decision,target,to_jsonb(previous),to_jsonb(changed));
  return jsonb_build_object('membership',to_jsonb(changed)-'user_id'-'reviewed_by');
end; $$;
revoke all on function public.delivery_cloud_membership(text,text,uuid,integer,text) from public,anon;
grant execute on function public.delivery_cloud_membership(text,text,uuid,integer,text) to authenticated;

-- Driver dispatch (20261116): approved application vehicle is forced, presence exposes approved_vehicle_type.
create or replace function public.delivery_driver_dispatch(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  a public.delivery_cloud_accounts;
  dp public.delivery_driver_presence;
  off public.delivery_driver_offers;
  o public.delivery_cloud_orders;
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  v_lat double precision;
  v_lng double precision;
  v_heading double precision;
  v_vehicle text;
  v_online boolean;
  v_batching boolean;
  v_active_count integer := 0;
  v_cand_order_id uuid;
  v_offer_json jsonb := null;
  v_decision text;
  v_ids uuid[];
  v_batch_id uuid;
  v_idx integer := 0;
  v_claimed jsonb := '[]'::jsonb;
  v_req_key uuid;
  prior public.delivery_cloud_commands;
  v_bundles jsonb := '[]'::jsonb;
  v_approved text;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id = uid;
  if not found or a.blocked or not public.delivery_cloud_has_membership(uid, 'driver') then
    raise sqlstate 'PT403' using message = 'Cần tài khoản đối tác tài xế đã được phê duyệt.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu điều phối tài xế không hợp lệ.';
  end if;

  -- Expire stale pending offers globally
  update public.delivery_driver_offers
    set state = 'expired', responded_at = coalesce(responded_at, now())
    where state = 'pending' and expires_at <= now();

  insert into public.delivery_driver_presence(user_id)
    values (uid)
    on conflict (user_id) do nothing;
  select * into dp from public.delivery_driver_presence where user_id = uid;

  -- An approved partner application pins the dispatch vehicle class (client value ignored)
  select ap.vehicle_type into v_approved
    from public.delivery_driver_applications ap
    where ap.user_id = uid and ap.state = 'approved';
  if v_approved is not null and dp.vehicle_type is distinct from v_approved then
    update public.delivery_driver_presence
      set vehicle_type = v_approved, updated_at = now()
      where user_id = uid
      returning * into dp;
  end if;

  select count(*)::integer into v_active_count
    from public.delivery_cloud_orders
    where driver_id = uid and status not in ('delivered', 'returned', 'cancelled');

  if p_action = 'get_presence' then
    return jsonb_build_object(
      'presence', to_jsonb(dp) || jsonb_build_object('approved_vehicle_type', v_approved),
      'active_trips_count', v_active_count,
      'server_now', now()
    );

  elsif p_action = 'set_presence' then
    v_online := coalesce((d->>'is_online')::boolean, dp.is_online);
    v_lat := coalesce((d->>'latitude')::double precision, dp.latitude);
    v_lng := coalesce((d->>'longitude')::double precision, dp.longitude);
    v_heading := coalesce((d->>'heading')::double precision, dp.heading);
    v_vehicle := case
      when v_approved is not null then v_approved
      else coalesce(nullif(d->>'vehicle_type', ''), dp.vehicle_type)
    end;
    v_batching := coalesce((d->>'allow_batching')::boolean, dp.allow_batching);

    if v_lat not between -90 and 90 or v_lng not between -180 and 180 or v_heading not between -360 and 360 then
      raise sqlstate 'PT400' using message = 'Tọa độ định vị tài xế không hợp lệ.';
    end if;
    if v_vehicle not in ('motorbike', 'ev_scooter', 'tricycle', 'van', 'truck') then
      raise sqlstate 'PT400' using message = 'Loại phương tiện tài xế không hợp lệ.';
    end if;

    update public.delivery_driver_presence
      set is_online = v_online,
          latitude = round(v_lat::numeric, 6)::double precision,
          longitude = round(v_lng::numeric, 6)::double precision,
          heading = round(v_heading::numeric, 1)::double precision,
          vehicle_type = v_vehicle,
          allow_batching = v_batching,
          last_seen_at = now(),
          updated_at = now()
      where user_id = uid
      returning * into dp;

    if not v_online then
      update public.delivery_driver_offers
        set state = 'cancelled', responded_at = now()
        where driver_id = uid and state = 'pending';
    elsif v_active_count = 0 then
      -- Proactively check if a nearby searching order can be offered immediately
      for v_cand_order_id in
        select so.id
        from public.delivery_cloud_orders so
        where so.status = 'searching'
          and so.merchant_ready
          and so.driver_id is null
          and so.fulfillment_provider is null
          and so.owner_id <> uid
          and jsonb_typeof(so.details->'pickup_lat') = 'number'
          and jsonb_typeof(so.details->'pickup_lng') = 'number'
          and public.delivery_haversine_meters(
                dp.latitude, dp.longitude,
                (so.details->>'pickup_lat')::double precision,
                (so.details->>'pickup_lng')::double precision
              ) <= 8000
        order by
          public.delivery_haversine_meters(
            dp.latitude, dp.longitude,
            (so.details->>'pickup_lat')::double precision,
            (so.details->>'pickup_lng')::double precision
          ) asc,
          so.created_at desc
        limit 8
      loop
        perform public.delivery_match_driver_offer_for_order(v_cand_order_id);
        exit when exists (
          select 1 from public.delivery_driver_offers
          where driver_id = uid and state = 'pending' and expires_at > now()
        );
      end loop;
    end if;

    return public.delivery_driver_dispatch('poll_offer', '{}'::jsonb);

  elsif p_action = 'poll_offer' then
    if jsonb_typeof(d->'latitude') = 'number' and jsonb_typeof(d->'longitude') = 'number' then
      v_lat := (d->>'latitude')::double precision;
      v_lng := (d->>'longitude')::double precision;
      if v_lat between -90 and 90 and v_lng between -180 and 180 then
        update public.delivery_driver_presence
          set latitude = round(v_lat::numeric, 6)::double precision,
              longitude = round(v_lng::numeric, 6)::double precision,
              heading = case
                when jsonb_typeof(d->'heading') = 'number'
                     and (d->>'heading')::double precision between -360 and 360
                  then round((d->>'heading')::numeric, 1)::double precision
                else heading
              end,
              last_seen_at = now(),
              updated_at = now()
          where user_id = uid
          returning * into dp;
      end if;
    elsif dp.is_online then
      update public.delivery_driver_presence
        set last_seen_at = now()
        where user_id = uid
        returning * into dp;
    end if;

    -- If online & idle & no active pending offer yet, try matching nearest searching order
    if dp.is_online and v_active_count = 0 and not exists (
      select 1 from public.delivery_driver_offers
      where driver_id = uid and state = 'pending' and expires_at > now()
    ) then
      for v_cand_order_id in
        select so.id
        from public.delivery_cloud_orders so
        where so.status = 'searching'
          and so.merchant_ready
          and so.driver_id is null
          and so.fulfillment_provider is null
          and so.owner_id <> uid
          and jsonb_typeof(so.details->'pickup_lat') = 'number'
          and jsonb_typeof(so.details->'pickup_lng') = 'number'
          and public.delivery_haversine_meters(
                dp.latitude, dp.longitude,
                (so.details->>'pickup_lat')::double precision,
                (so.details->>'pickup_lng')::double precision
              ) <= 8000
        order by
          public.delivery_haversine_meters(
            dp.latitude, dp.longitude,
            (so.details->>'pickup_lat')::double precision,
            (so.details->>'pickup_lng')::double precision
          ) asc,
          so.created_at desc
        limit 8
      loop
        perform public.delivery_match_driver_offer_for_order(v_cand_order_id);
        exit when exists (
          select 1 from public.delivery_driver_offers
          where driver_id = uid and state = 'pending' and expires_at > now()
        );
      end loop;
    end if;

    select * into off
      from public.delivery_driver_offers
      where driver_id = uid and state = 'pending' and expires_at > now()
      order by created_at desc
      limit 1;

    if found then
      select * into o from public.delivery_cloud_orders where id = off.order_id;
      if found and o.status = 'searching' and o.driver_id is null and o.merchant_ready then
        v_offer_json := jsonb_build_object(
          'id', off.id,
          'order_id', o.id,
          'tracking_code', o.tracking_code,
          'distance_to_pickup_meters', off.distance_meters,
          'order_distance_meters', o.distance_meters,
          'radius_tier_km', off.radius_tier_km,
          'shipping_fee', o.shipping_fee,
          'payable_fee', o.payable_fee,
          'cod_amount', o.cod_amount,
          'estimated_earning', off.estimated_earning,
          'service_type', coalesce(o.details->>'service_type', 'standard'),
          'vehicle_type', public.delivery_order_vehicle_type(o.details),
          'payment_method', coalesce(o.details->>'payment_method', 'sender_cash'),
          'prefer_ev', coalesce((o.details->>'prefer_ev')::boolean, false),
          'require_pod', coalesce((o.details->>'require_pod')::boolean, false),
          'require_otp', coalesce((o.details->>'require_otp')::boolean, false),
          'require_signature', coalesce((o.details->>'require_signature')::boolean, false),
          'pickup_area', coalesce(public.delivery_coarse_area(o.details->>'pickup_address'), left(coalesce(o.details->>'pickup_address', ''), 48)),
          'dropoff_area', coalesce(public.delivery_coarse_area(o.details->>'dropoff_address'), left(coalesce(o.details->>'dropoff_address', ''), 48)),
          'expires_at', off.expires_at,
          'remaining_seconds', greatest(1, ceil(extract(epoch from (off.expires_at - now()))))::integer
        );
      else
        update public.delivery_driver_offers
          set state = 'cancelled', responded_at = now()
          where id = off.id;
      end if;
    end if;

    return jsonb_build_object(
      'presence', to_jsonb(dp) || jsonb_build_object('approved_vehicle_type', v_approved),
      'active_trips_count', v_active_count,
      'active_offer', v_offer_json,
      'server_now', now()
    );

  elsif p_action = 'respond_offer' then
    if jsonb_typeof(d->'offer_id') <> 'string' or coalesce(d->>'decision', '') not in ('accept', 'reject') then
      raise sqlstate 'PT400' using message = 'Phản hồi đề xuất cuốc không hợp lệ.';
    end if;
    v_decision := d->>'decision';

    perform pg_advisory_xact_lock(hashtextextended('driver:' || uid::text, 0));
    select * into off
      from public.delivery_driver_offers
      where id = (d->>'offer_id')::uuid and driver_id = uid
      for update;

    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy đề xuất cuốc giao.';
    end if;
    if off.state = 'accepted' and v_decision = 'accept' then
      select * into o from public.delivery_cloud_orders where id = off.order_id;
      return jsonb_build_object('accepted', true, 'order', public.delivery_cloud_order_enriched(o));
    end if;
    if off.state <> 'pending' or off.expires_at <= now() then
      update public.delivery_driver_offers
        set state = case when state = 'pending' then 'expired' else state end,
            responded_at = coalesce(responded_at, now())
        where id = off.id;
      raise sqlstate 'PT409' using message = 'Đề xuất cuốc đã hết hạn 28 giây hoặc không còn khả dụng.';
    end if;

    if v_decision = 'reject' then
      update public.delivery_driver_offers
        set state = 'rejected', responded_at = now()
        where id = off.id;
      -- Immediately dispatch to the next best online driver
      perform public.delivery_match_driver_offer_for_order(off.order_id);
      return jsonb_build_object('accepted', false, 'rejected', true, 'offer_id', off.id);
    end if;

    if v_active_count > 0 then
      raise sqlstate 'PT409' using message = 'Bạn đang có chuyến chưa hoàn tất.';
    end if;

    select * into o from public.delivery_cloud_orders where id = off.order_id for update;
    if not found or o.status <> 'searching' or not o.merchant_ready or o.driver_id is not null or o.fulfillment_provider is not null then
      update public.delivery_driver_offers
        set state = 'cancelled', responded_at = now()
        where id = off.id;
      raise sqlstate 'PT409' using message = 'Cuốc xe vừa được nhận hoặc hủy.';
    end if;

    update public.delivery_cloud_orders
      set status = 'accepted',
          driver_id = uid,
          version = version + 1,
          updated_at = now()
      where id = o.id
      returning * into o;

    update public.delivery_driver_offers
      set state = 'accepted', responded_at = now()
      where id = off.id;

    insert into public.delivery_live_rooms(id) values (o.tracking_code) on conflict do nothing;
    insert into public.delivery_live_members values (o.tracking_code, uid, 'driver')
      on conflict (room_id, user_id) do update set role = 'driver';
    insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
      values (o.id, uid, 'claim', o.status, o.version, 'Nhận cuốc điều phối tự động GPS (' || off.radius_tier_km || ' km)');
    insert into public.delivery_live_events(room_id, kind, payload)
      values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));

    return jsonb_build_object(
      'accepted', true,
      'order', public.delivery_cloud_order_enriched(o)
    );

  elsif p_action = 'batch_suggestions' then
    with eligible as (
      select
        so.id,
        so.tracking_code,
        so.shipping_fee,
        so.cod_amount,
        so.distance_meters,
        so.created_at,
        coalesce(so.details->>'service_type', 'standard') as service_type,
        (so.details->>'pickup_lat')::double precision as plat,
        (so.details->>'pickup_lng')::double precision as plng,
        (so.details->>'dropoff_lat')::double precision as dlat,
        (so.details->>'dropoff_lng')::double precision as dlng,
        coalesce(public.delivery_coarse_area(so.details->>'pickup_address'), left(coalesce(so.details->>'pickup_address', ''), 40)) as pickup_area,
        coalesce(public.delivery_coarse_area(so.details->>'dropoff_address'), left(coalesce(so.details->>'dropoff_address', ''), 40)) as dropoff_area,
        public.delivery_route_bearing_deg(
          (so.details->>'pickup_lat')::double precision,
          (so.details->>'pickup_lng')::double precision,
          (so.details->>'dropoff_lat')::double precision,
          (so.details->>'dropoff_lng')::double precision
        ) as bearing_deg
      from public.delivery_cloud_orders so
      where so.status = 'searching'
        and so.merchant_ready
        and so.driver_id is null
        and so.fulfillment_provider is null
        and so.owner_id <> uid
        and coalesce(so.details->>'service_type', 'standard') in ('saving', 'standard', 'same_day_2h')
        and not coalesce((so.details->>'is_round_trip')::boolean, false)
        and public.delivery_vehicle_can_serve(dp.vehicle_type, public.delivery_order_vehicle_type(so.details))
        and jsonb_typeof(so.details->'pickup_lat') = 'number'
        and jsonb_typeof(so.details->'pickup_lng') = 'number'
        and jsonb_typeof(so.details->'dropoff_lat') = 'number'
        and jsonb_typeof(so.details->'dropoff_lng') = 'number'
        and not exists (
          select 1 from public.delivery_payment_transactions pt
          where pt.order_id = so.id and pt.status in ('CREATING', 'PENDING', 'REVIEW')
        )
      order by so.created_at desc
      limit 30
    ),
    pairs as (
      select
        e1.id as id1,
        e2.id as id2,
        e1.tracking_code as tc1,
        e2.tracking_code as tc2,
        e1.pickup_area as p1,
        e2.pickup_area as p2,
        e1.dropoff_area as d1,
        e2.dropoff_area as d2,
        e1.shipping_fee + e2.shipping_fee as total_shipping_fee,
        round((e1.shipping_fee + e2.shipping_fee) * 0.80)::bigint as total_driver_earning,
        e1.cod_amount + e2.cod_amount as total_cod_amount,
        public.delivery_haversine_meters(e1.plat, e1.plng, e2.plat, e2.plng) as pickup_gap_meters,
        public.delivery_haversine_meters(e1.dlat, e1.dlng, e2.dlat, e2.dlng) as dropoff_gap_meters,
        least(
          abs(e1.bearing_deg - e2.bearing_deg),
          360.0 - abs(e1.bearing_deg - e2.bearing_deg)
        ) as bearing_delta_deg,
        e1.distance_meters + e2.distance_meters as sum_single_meters,
        (
          public.delivery_haversine_meters(dp.latitude, dp.longitude, e1.plat, e1.plng)
          + public.delivery_haversine_meters(e1.plat, e1.plng, e2.plat, e2.plng)
          + public.delivery_haversine_meters(e2.plat, e2.plng, e1.dlat, e1.dlng)
          + public.delivery_haversine_meters(e1.dlat, e1.dlng, e2.dlat, e2.dlng)
        ) as corridor_meters
      from eligible e1
      join eligible e2 on e1.id < e2.id
      where public.delivery_haversine_meters(e1.plat, e1.plng, e2.plat, e2.plng) <= 3000
        and least(
              abs(e1.bearing_deg - e2.bearing_deg),
              360.0 - abs(e1.bearing_deg - e2.bearing_deg)
            ) <= 55.0
      order by pickup_gap_meters asc, bearing_delta_deg asc
      limit 6
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'bundle_key', pr.id1::text || ':' || pr.id2::text,
      'order_ids', jsonb_build_array(pr.id1, pr.id2),
      'tracking_codes', jsonb_build_array(pr.tc1, pr.tc2),
      'order_count', 2,
      'pickup_summary', coalesce(pr.p1, 'Điểm lấy #1') || ' -> ' || coalesce(pr.p2, 'Điểm lấy #2'),
      'dropoff_summary', coalesce(pr.d1, 'Điểm giao #1') || ' -> ' || coalesce(pr.d2, 'Điểm giao #2'),
      'pickup_gap_meters', pr.pickup_gap_meters,
      'dropoff_gap_meters', pr.dropoff_gap_meters,
      'bearing_delta_deg', round(pr.bearing_delta_deg::numeric, 1),
      'corridor_meters', pr.corridor_meters,
      'total_shipping_fee', pr.total_shipping_fee,
      'estimated_earning', pr.total_driver_earning,
      'total_cod_amount', pr.total_cod_amount
    )), '[]'::jsonb)
    into v_bundles
    from pairs pr;

    return jsonb_build_object(
      'bundles', v_bundles,
      'active_trips_count', v_active_count
    );

  elsif p_action = 'claim_batch' then
    if jsonb_typeof(d->'order_ids') <> 'array' or jsonb_array_length(d->'order_ids') not between 2 and 3 then
      raise sqlstate 'PT400' using message = 'Ghép đơn cùng tuyến hỗ trợ từ 2 đến 3 vận đơn.';
    end if;
    v_req_key := coalesce(nullif(d->>'request_key', '')::uuid, gen_random_uuid());

    perform pg_advisory_xact_lock(hashtextextended(uid::text || v_req_key::text, 0));
    select * into prior
      from public.delivery_cloud_commands
      where actor_id = uid and request_key = v_req_key;
    if found then
      return prior.response;
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver:' || uid::text, 0));
    if v_active_count > 0 then
      raise sqlstate 'PT409' using message = 'Bạn đang có chuyến chưa hoàn tất, hãy hoàn thành trước khi nhận cụm đơn mới.';
    end if;

    select array_agg(distinct (elem)::uuid order by (elem)::uuid)
      into v_ids
      from jsonb_array_elements_text(d->'order_ids') as elem;

    if coalesce(array_length(v_ids, 1), 0) not between 2 and 3 then
      raise sqlstate 'PT400' using message = 'Danh sách mã vận đơn ghép tuyến bị trùng hoặc không hợp lệ.';
    end if;

    v_batch_id := gen_random_uuid();
    for v_idx in 1..array_length(v_ids, 1) loop
      select * into o
        from public.delivery_cloud_orders
        where id = v_ids[v_idx]
        for update;

      if not found
         or o.status <> 'searching'
         or not o.merchant_ready
         or o.driver_id is not null
         or o.fulfillment_provider is not null
         or o.owner_id = uid
         or coalesce(o.details->>'service_type', 'standard') = 'truck'
         or coalesce((o.details->>'is_round_trip')::boolean, false)
         or not public.delivery_vehicle_can_serve(dp.vehicle_type, public.delivery_order_vehicle_type(o.details)) then
        raise sqlstate 'PT409' using message = 'Một trong các vận đơn ghép tuyến không còn khả dụng hoặc không hỗ trợ ghép chuyến.';
      end if;

      update public.delivery_cloud_orders
        set status = 'accepted',
            driver_id = uid,
            batch_group_id = v_batch_id,
            batch_sequence = v_idx,
            version = version + 1,
            updated_at = now()
        where id = o.id
        returning * into o;

      insert into public.delivery_live_rooms(id) values (o.tracking_code) on conflict do nothing;
      insert into public.delivery_live_members values (o.tracking_code, uid, 'driver')
        on conflict (room_id, user_id) do update set role = 'driver';
      insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
        values (o.id, uid, 'claim', o.status, o.version, 'Nhận cụm đơn ghép cùng tuyến #' || v_idx || '/' || array_length(v_ids, 1));
      insert into public.delivery_live_events(room_id, kind, payload)
        values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));

      v_claimed := v_claimed || jsonb_build_array(public.delivery_cloud_order_enriched(o));
    end loop;

    prior.response := jsonb_build_object(
      'batch_group_id', v_batch_id,
      'orders', v_claimed
    );
    insert into public.delivery_cloud_commands values (
      uid, v_req_key, jsonb_build_object('action', 'claim_batch', 'order_ids', to_jsonb(v_ids)), prior.response, now()
    );
    return prior.response;

  else
    raise sqlstate 'PT400' using message = 'Thao tác điều phối tài xế không hợp lệ.';
  end if;
end; $$;

revoke all on function public.delivery_driver_dispatch(text, jsonb) from public, anon;
grant execute on function public.delivery_driver_dispatch(text, jsonb) to authenticated;

-- ============================================================================
-- PART 5: DRIVER PARTNER APPLICATION RPC
-- ============================================================================

create or replace function public.delivery_driver_application(
  p_action text,
  p_details jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  d jsonb := coalesce(p_details, '{}'::jsonb);
  a public.delivery_cloud_accounts;
  app public.delivery_driver_applications;
  kinds constant text[] := array['citizen_front', 'citizen_back', 'license', 'vehicle_registration', 'portrait'];
  fields constant text[] := array['vehicle_type', 'license_plate', 'vehicle_brand', 'vehicle_color',
    'license_number', 'license_class', 'operating_area', 'documents'];
  v_prefix text;
  v_vehicle text;
  v_plate text;
  v_brand text;
  v_color text;
  v_license text;
  v_class text;
  v_area text;
  v_docs jsonb;
  v_key text;
  v_state text;
  v_target uuid;
  result jsonb;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000 then
    raise sqlstate 'PT400' using message = 'Hồ sơ đối tác tài xế không hợp lệ.';
  end if;
  v_prefix := 'driver-applications/' || uid::text || '/';

  if p_action = 'get' then
    if d <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Yêu cầu hồ sơ tài xế không hợp lệ.';
    end if;
    select * into app from public.delivery_driver_applications where user_id = uid;
    return jsonb_build_object('application', public.delivery_driver_application_payload(app));

  elsif p_action = 'upload_document' then
    -- Reserves a private object path; the gateway uploads the re-encoded image with the user JWT.
    if d - 'kind' <> '{}'::jsonb or jsonb_typeof(d->'kind') is distinct from 'string'
       or not ((d->>'kind') = any(kinds)) then
      raise sqlstate 'PT400' using message = 'Loại giấy tờ không hợp lệ.';
    end if;
    select * into a from public.delivery_cloud_accounts where user_id = uid;
    if not found then
      raise sqlstate 'PT404' using message = 'Cần hoàn thiện hồ sơ trước.';
    end if;
    if a.blocked then
      raise sqlstate 'PT403' using message = 'Tài khoản đang khóa.';
    end if;
    select * into app from public.delivery_driver_applications where user_id = uid;
    if found and app.state in ('pending', 'approved') then
      raise sqlstate 'PT409' using message = 'Hồ sơ tài xế đang chờ duyệt hoặc đã được duyệt, không thể thay giấy tờ.';
    end if;
    return jsonb_build_object(
      'bucket', 'delivery-private-evidence',
      'kind', d->>'kind',
      'path', v_prefix || (d->>'kind') || '-' || gen_random_uuid()::text || '.webp'
    );

  elsif p_action = 'submit' then
    if not (d ?& fields) or d - fields <> '{}'::jsonb
       or jsonb_typeof(d->'vehicle_type') <> 'string' or jsonb_typeof(d->'license_plate') <> 'string'
       or jsonb_typeof(d->'vehicle_brand') <> 'string' or jsonb_typeof(d->'vehicle_color') <> 'string'
       or jsonb_typeof(d->'license_number') <> 'string' or jsonb_typeof(d->'license_class') <> 'string'
       or jsonb_typeof(d->'operating_area') <> 'string' or jsonb_typeof(d->'documents') <> 'object' then
      raise sqlstate 'PT400' using message = 'Hồ sơ đối tác tài xế không hợp lệ.';
    end if;

    v_vehicle := d->>'vehicle_type';
    if v_vehicle not in ('motorbike', 'ev_scooter', 'tricycle', 'van', 'truck') then
      raise sqlstate 'PT400' using message = 'Loại phương tiện không hợp lệ.';
    end if;
    v_plate := upper(regexp_replace(d->>'license_plate', '\s', '', 'g'));
    if v_plate !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?-?[0-9]{3}\.?[0-9]{2}$'
       and v_plate !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?-?[0-9]{4}$' then
      raise sqlstate 'PT400' using message = 'Biển số xe không hợp lệ (ví dụ 59X1-123.45 hoặc 51C-123.45).';
    end if;
    v_license := btrim(d->>'license_number');
    if v_license !~ '^[0-9]{12}$' then
      raise sqlstate 'PT400' using message = 'Số giấy phép lái xe phải gồm đúng 12 chữ số.';
    end if;
    v_brand := btrim(d->>'vehicle_brand');
    if char_length(v_brand) not between 2 and 60 then
      raise sqlstate 'PT400' using message = 'Hãng và dòng xe cần từ 2 đến 60 ký tự.';
    end if;
    v_color := btrim(d->>'vehicle_color');
    if char_length(v_color) not between 2 and 30 then
      raise sqlstate 'PT400' using message = 'Màu xe cần từ 2 đến 30 ký tự.';
    end if;
    v_area := btrim(d->>'operating_area');
    if char_length(v_area) not between 2 and 120 then
      raise sqlstate 'PT400' using message = 'Khu vực hoạt động cần từ 2 đến 120 ký tự.';
    end if;
    v_class := upper(btrim(d->>'license_class'));
    if not coalesce(case v_vehicle
      when 'motorbike' then v_class in ('A1', 'A', 'A2')
      when 'ev_scooter' then v_class in ('A1', 'A', 'A2')
      when 'tricycle' then v_class in ('A1', 'A', 'B', 'B1', 'B2')
      when 'van' then v_class in ('B', 'B1', 'B2', 'C1')
      when 'truck' then v_class in ('C1', 'C')
      else false
    end, false) then
      raise sqlstate 'PT400' using message = 'Hạng giấy phép lái xe không phù hợp với loại phương tiện đã chọn.';
    end if;

    v_docs := d->'documents';
    if (select count(*) from jsonb_object_keys(v_docs)) <> 5 or not (v_docs ?& kinds) then
      raise sqlstate 'PT400' using message = 'Cần đủ 5 ảnh: CCCD mặt trước, CCCD mặt sau, giấy phép lái xe, đăng ký xe và ảnh chân dung.';
    end if;
    foreach v_key in array kinds loop
      if jsonb_typeof(v_docs->v_key) is distinct from 'string'
         or left(v_docs->>v_key, length(v_prefix)) <> v_prefix
         or substr(v_docs->>v_key, length(v_prefix) + 1)
              !~ ('^' || v_key || '-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg|jpeg|png)$') then
        raise sqlstate 'PT400' using message = 'Đường dẫn ảnh giấy tờ không hợp lệ.';
      end if;
    end loop;

    select * into a from public.delivery_cloud_accounts where user_id = uid;
    if not found then
      raise sqlstate 'PT404' using message = 'Cần hoàn thiện hồ sơ trước.';
    end if;
    if a.blocked then
      raise sqlstate 'PT403' using message = 'Tài khoản đang khóa.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver:' || uid::text, 0));
    select * into app from public.delivery_driver_applications where user_id = uid for update;
    if found and app.state = 'pending' then
      raise sqlstate 'PT409' using message = 'Hồ sơ tài xế đang chờ duyệt.';
    end if;
    if found and app.state = 'approved' then
      raise sqlstate 'PT409' using message = 'Hồ sơ tài xế đã được duyệt.';
    end if;

    insert into public.delivery_driver_applications(
      user_id, vehicle_type, license_plate, vehicle_brand, vehicle_color, license_number,
      license_class, operating_area, documents, state, reason, version, submitted_at,
      reviewed_at, reviewed_by, updated_at
    ) values (
      uid, v_vehicle, v_plate, v_brand, v_color, v_license,
      v_class, v_area, v_docs, 'pending', '', 1, now(),
      null, null, now()
    )
    on conflict (user_id) do update
      set vehicle_type = excluded.vehicle_type,
          license_plate = excluded.license_plate,
          vehicle_brand = excluded.vehicle_brand,
          vehicle_color = excluded.vehicle_color,
          license_number = excluded.license_number,
          license_class = excluded.license_class,
          operating_area = excluded.operating_area,
          documents = excluded.documents,
          state = 'pending',
          reason = '',
          version = public.delivery_driver_applications.version + 1,
          submitted_at = now(),
          reviewed_at = null,
          reviewed_by = null,
          updated_at = now()
    returning * into app;

    -- Same behaviour as POST /memberships {role:'driver'}
    perform public.delivery_cloud_membership('driver', 'request');

    return jsonb_build_object('application', public.delivery_driver_application_payload(app));

  elsif p_action = 'admin_list' then
    if not public.delivery_is_operator() then
      raise sqlstate 'PT403' using message = 'Cần quyền quản trị.';
    end if;
    if d - 'state' <> '{}'::jsonb or (d ? 'state' and (
         jsonb_typeof(d->'state') is distinct from 'string'
         or (d->>'state') not in ('pending', 'approved', 'rejected'))) then
      raise sqlstate 'PT400' using message = 'Bộ lọc hồ sơ tài xế không hợp lệ.';
    end if;
    v_state := d->>'state';
    select coalesce(jsonb_agg(x.item order by x.submitted_at desc, x.user_id), '[]'::jsonb)
      into result
      from (
        select ap.submitted_at, ap.user_id,
          jsonb_build_object(
            'user_id', ap.user_id,
            'full_name', coalesce(ac.full_name, ''),
            'phone', coalesce(ac.phone, ''),
            'membership_version', coalesce(m.version, 0),
            'membership_state', m.state
          ) || public.delivery_driver_application_payload(ap) as item
        from public.delivery_driver_applications ap
        left join public.delivery_cloud_accounts ac on ac.user_id = ap.user_id
        left join public.delivery_cloud_memberships m on m.user_id = ap.user_id and m.role = 'driver'
        where v_state is null or ap.state = v_state
        order by ap.submitted_at desc, ap.user_id
        limit 200
      ) x;
    return jsonb_build_object('applications', result);

  elsif p_action = 'admin_get' then
    if not public.delivery_is_operator() then
      raise sqlstate 'PT403' using message = 'Cần quyền quản trị.';
    end if;
    if d - 'user_id' <> '{}'::jsonb or jsonb_typeof(d->'user_id') is distinct from 'string'
       or (d->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise sqlstate 'PT400' using message = 'Mã tài khoản không hợp lệ.';
    end if;
    v_target := (d->>'user_id')::uuid;
    select jsonb_build_object(
        'user_id', ap.user_id,
        'full_name', coalesce(ac.full_name, ''),
        'phone', coalesce(ac.phone, ''),
        'membership_version', coalesce(m.version, 0),
        'membership_state', m.state
      ) || public.delivery_driver_application_payload(ap)
      into result
      from public.delivery_driver_applications ap
      left join public.delivery_cloud_accounts ac on ac.user_id = ap.user_id
      left join public.delivery_cloud_memberships m on m.user_id = ap.user_id and m.role = 'driver'
      where ap.user_id = v_target;
    if result is null then
      raise sqlstate 'PT404' using message = 'Không tìm thấy hồ sơ tài xế.';
    end if;
    return jsonb_build_object('application', result);

  else
    raise sqlstate 'PT400' using message = 'Thao tác hồ sơ tài xế không hợp lệ.';
  end if;
end; $$;

revoke all on function public.delivery_driver_application(text, jsonb) from public, anon;
grant execute on function public.delivery_driver_application(text, jsonb) to authenticated;

commit;
