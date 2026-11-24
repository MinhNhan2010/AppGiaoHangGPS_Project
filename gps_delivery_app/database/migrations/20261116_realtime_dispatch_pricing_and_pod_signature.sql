-- Additive migration: Real-time GPS Proximity Auto-Dispatch & 28s Exclusive Driver Offers,
-- Multi-Order Corridor Route Batching (Trip Bundle), Operator Dynamic Pricing Rules &
-- Polygon Geofence Surge Zones, Recipient Touch Signature on Cloud POD, and Masked Contact.
-- Safe to reapply; seeds zero operational rows automatically during migration (clean-start preserved).
begin;

-- ============================================================================
-- PART 1: GEODESIC, BEARING, POINT-IN-POLYGON & PHONE MASKING HELPERS
-- ============================================================================

create or replace function public.delivery_mask_phone(p_phone text) returns text
language plpgsql immutable set search_path='' as $$
declare
  cleaned text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  len integer;
begin
  len := length(cleaned);
  if len < 7 then
    return case when len = 0 then '' else '***' end;
  end if;
  return left(cleaned, 4) || '***' || right(cleaned, 3);
end; $$;

revoke all on function public.delivery_mask_phone(text) from public, anon, authenticated;

create or replace function public.delivery_haversine_meters(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
) returns integer
language plpgsql immutable set search_path='' as $$
declare
  a double precision;
begin
  if p_lat1 is null or p_lng1 is null or p_lat2 is null or p_lng2 is null then
    return 99999999;
  end if;
  a := power(sin(radians(p_lat2 - p_lat1) / 2.0), 2)
     + cos(radians(p_lat1)) * cos(radians(p_lat2))
     * power(sin(radians(p_lng2 - p_lng1) / 2.0), 2);
  return ceil(6371000.0 * 2.0 * asin(sqrt(least(1.0, greatest(0.0, a)))))::integer;
end; $$;

revoke all on function public.delivery_haversine_meters(double precision, double precision, double precision, double precision) from public, anon, authenticated;

create or replace function public.delivery_route_bearing_deg(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
) returns double precision
language plpgsql immutable set search_path='' as $$
declare
  dlon double precision;
  y double precision;
  x double precision;
  brng double precision;
begin
  if p_lat1 is null or p_lng1 is null or p_lat2 is null or p_lng2 is null then
    return 0;
  end if;
  dlon := radians(p_lng2 - p_lng1);
  y := sin(dlon) * cos(radians(p_lat2));
  x := cos(radians(p_lat1)) * sin(radians(p_lat2))
     - sin(radians(p_lat1)) * cos(radians(p_lat2)) * cos(dlon);
  brng := degrees(atan2(y, x));
  return mod((brng + 360.0)::numeric, 360.0)::double precision;
end; $$;

revoke all on function public.delivery_route_bearing_deg(double precision, double precision, double precision, double precision) from public, anon, authenticated;

create or replace function public.delivery_point_in_polygon(
  p_lat double precision,
  p_lng double precision,
  p_polygon jsonb
) returns boolean
language plpgsql immutable set search_path='' as $$
declare
  n integer;
  inside boolean := false;
  i integer;
  j integer;
  yi double precision;
  xi double precision;
  yj double precision;
  xj double precision;
  vi jsonb;
  vj jsonb;
begin
  if p_lat is null or p_lng is null or jsonb_typeof(p_polygon) is distinct from 'array' then
    return false;
  end if;
  n := jsonb_array_length(p_polygon);
  if n < 3 then
    return false;
  end if;
  j := n - 1;
  for i in 0..(n - 1) loop
    vi := p_polygon->i;
    vj := p_polygon->j;
    if jsonb_typeof(vi->'lat') = 'number' and jsonb_typeof(vi->'lng') = 'number'
       and jsonb_typeof(vj->'lat') = 'number' and jsonb_typeof(vj->'lng') = 'number' then
      yi := (vi->>'lat')::double precision;
      xi := (vi->>'lng')::double precision;
      yj := (vj->>'lat')::double precision;
      xj := (vj->>'lng')::double precision;
      if ((yi > p_lat) <> (yj > p_lat))
         and (p_lng < (xj - xi) * (p_lat - yi) / nullif(yj - yi, 0.0) + xi) then
        inside := not inside;
      end if;
    end if;
    j := i;
  end loop;
  return inside;
end; $$;

revoke all on function public.delivery_point_in_polygon(double precision, double precision, jsonb) from public, anon, authenticated;

-- ============================================================================
-- PART 2: DYNAMIC PRICING RULES & POLYGON GEOFENCE SURGE ZONES
-- ============================================================================

create table if not exists public.delivery_cloud_pricing_rules (
  service_type text primary key check (service_type in ('standard', 'express', 'saving', 'same_day_2h', 'truck')),
  base_fee integer not null check (base_fee between 0 and 2000000),
  per_km integer not null check (per_km between 0 and 200000),
  free_km numeric(4,1) not null default 2.0 check (free_km between 0 and 20),
  extra_kg integer not null check (extra_kg between 0 and 200000),
  free_weight_kg numeric(5,1) not null default 5.0 check (free_weight_kg between 0 and 500),
  peak_multiplier_bps integer not null default 10000 check (peak_multiplier_bps between 10000 and 30000),
  peak_enabled boolean not null default false,
  weather_surcharge integer not null default 0 check (weather_surcharge between 0 and 200000),
  weather_enabled boolean not null default false,
  weather_label text not null default 'Phụ phí thời tiết mưa bão' check (length(weather_label) <= 120),
  active boolean not null default true,
  version integer not null default 1 check (version >= 1),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_cloud_geofences (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 2 and 120),
  zone_type text not null default 'surge' check (zone_type in ('surge', 'weather', 'restricted_surcharge', 'priority')),
  surcharge_fee integer not null default 0 check (surcharge_fee between 0 and 500000),
  multiplier_bps integer not null default 10000 check (multiplier_bps between 10000 and 30000),
  polygon jsonb not null check (jsonb_typeof(polygon) = 'array' and jsonb_array_length(polygon) between 3 and 24),
  active boolean not null default true,
  version integer not null default 1 check (version >= 1),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create index if not exists delivery_cloud_geofences_active_idx
  on public.delivery_cloud_geofences(active, updated_at desc);

alter table public.delivery_cloud_pricing_rules enable row level security;
alter table public.delivery_cloud_geofences enable row level security;

revoke all on table
  public.delivery_cloud_pricing_rules,
  public.delivery_cloud_geofences
from public, anon, authenticated;

create or replace function public.delivery_admin_pricing(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  p public.delivery_cloud_pricing;
  r public.delivery_cloud_pricing_rules;
  g public.delivery_cloud_geofences;
  v_service text;
  v_poly jsonb;
  v_pt jsonb;
  v_lat double precision;
  v_lng double precision;
  v_id uuid;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 16000 then
    raise sqlstate 'PT400' using message = 'Dữ liệu cấu hình bảng giá không hợp lệ.';
  end if;

  if p_action = 'public_zones' then
    return jsonb_build_object(
      'geofences', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', gz.id,
          'name', gz.name,
          'zone_type', gz.zone_type,
          'surcharge_fee', gz.surcharge_fee,
          'multiplier_bps', gz.multiplier_bps,
          'polygon', gz.polygon,
          'active', gz.active
        ) order by gz.updated_at desc, gz.id desc)
        from public.delivery_cloud_geofences gz
        where gz.active
      ), '[]'::jsonb)
    );
  end if;

  if not op then
    raise sqlstate 'PT403' using message = 'Chỉ Điều hành viên được cấu hình bảng giá động và vùng phụ phí.';
  end if;

  select * into p from public.delivery_cloud_pricing where id;

  if p_action = 'get' then
    return jsonb_build_object(
      'base_pricing', to_jsonb(p),
      'rules', coalesce((
        select jsonb_agg(to_jsonb(pr) order by pr.service_type asc)
        from public.delivery_cloud_pricing_rules pr
      ), '[]'::jsonb),
      'geofences', coalesce((
        select jsonb_agg(to_jsonb(gz) order by gz.updated_at desc, gz.id desc)
        from public.delivery_cloud_geofences gz
      ), '[]'::jsonb)
    );

  elsif p_action = 'save_rule' then
    v_service := coalesce(d->>'service_type', '');
    if v_service not in ('standard', 'express', 'saving', 'same_day_2h', 'truck') then
      raise sqlstate 'PT400' using message = 'Gói dịch vụ không hợp lệ.';
    end if;
    if jsonb_typeof(d->'base_fee') <> 'number' or jsonb_typeof(d->'per_km') <> 'number'
       or (d->>'base_fee')::integer not between 0 and 2000000
       or (d->>'per_km')::integer not between 0 and 200000 then
      raise sqlstate 'PT400' using message = 'Giá mở cửa hoặc đơn giá mỗi km không hợp lệ.';
    end if;

    insert into public.delivery_cloud_pricing_rules(
      service_type, base_fee, per_km, free_km, extra_kg, free_weight_kg,
      peak_multiplier_bps, peak_enabled, weather_surcharge, weather_enabled,
      weather_label, active, version, updated_by, updated_at
    ) values (
      v_service,
      (d->>'base_fee')::integer,
      (d->>'per_km')::integer,
      coalesce((d->>'free_km')::numeric, 2.0),
      coalesce((d->>'extra_kg')::integer, p.extra_kg),
      coalesce((d->>'free_weight_kg')::numeric, case when v_service = 'truck' then 20.0 else 5.0 end),
      coalesce((d->>'peak_multiplier_bps')::integer, 10000),
      coalesce((d->>'peak_enabled')::boolean, false),
      coalesce((d->>'weather_surcharge')::integer, 0),
      coalesce((d->>'weather_enabled')::boolean, false),
      left(btrim(coalesce(nullif(d->>'weather_label', ''), 'Phụ phí thời tiết mưa bão')), 120),
      coalesce((d->>'active')::boolean, true),
      1,
      uid,
      now()
    )
    on conflict (service_type) do update set
      base_fee = excluded.base_fee,
      per_km = excluded.per_km,
      free_km = excluded.free_km,
      extra_kg = excluded.extra_kg,
      free_weight_kg = excluded.free_weight_kg,
      peak_multiplier_bps = excluded.peak_multiplier_bps,
      peak_enabled = excluded.peak_enabled,
      weather_surcharge = excluded.weather_surcharge,
      weather_enabled = excluded.weather_enabled,
      weather_label = excluded.weather_label,
      active = excluded.active,
      version = public.delivery_cloud_pricing_rules.version + 1,
      updated_by = uid,
      updated_at = now()
    returning * into r;

    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'pricing_rule_save', null, to_jsonb(r));

    return public.delivery_admin_pricing('get', '{}'::jsonb);

  elsif p_action = 'toggle_surge' then
    if d ? 'peak_enabled' and jsonb_typeof(d->'peak_enabled') <> 'boolean' then
      raise sqlstate 'PT400' using message = 'Cờ giờ cao điểm không hợp lệ.';
    end if;
    if d ? 'weather_enabled' and jsonb_typeof(d->'weather_enabled') <> 'boolean' then
      raise sqlstate 'PT400' using message = 'Cờ phụ phí thời tiết không hợp lệ.';
    end if;

    -- Ensure all 5 service rules exist if operator toggles global surge before customizing individual tiers
    insert into public.delivery_cloud_pricing_rules(
      service_type, base_fee, per_km, free_km, extra_kg, free_weight_kg,
      peak_multiplier_bps, peak_enabled, weather_surcharge, weather_enabled, updated_by
    )
    values
      ('saving', greatest(12000, round(p.base_fee * 0.48)::integer), greatest(4000, round(p.per_km * 0.80)::integer), 2.0, p.extra_kg, 5.0, 12000, false, 8000, false, uid),
      ('standard', p.base_fee, p.per_km, 2.0, p.extra_kg, 5.0, 12500, false, 10000, false, uid),
      ('same_day_2h', greatest(12000, round(p.base_fee * 0.48)::integer), greatest(5500, round(p.per_km * 1.10)::integer), 2.0, p.extra_kg, 5.0, 12500, false, 10000, false, uid),
      ('express', p.base_fee + p.express_fee, p.per_km, 2.0, p.extra_kg, 5.0, 13500, false, 12000, false, uid),
      ('truck', greatest(80000, p.base_fee * 3 + 5000), p.per_km * 3, 2.0, p.extra_kg, 20.0, 12000, false, 25000, false, uid)
    on conflict (service_type) do nothing;

    update public.delivery_cloud_pricing_rules
      set peak_enabled = coalesce((d->>'peak_enabled')::boolean, peak_enabled),
          peak_multiplier_bps = case
            when jsonb_typeof(d->'peak_multiplier_bps') = 'number'
                 and (d->>'peak_multiplier_bps')::integer between 10000 and 30000
              then (d->>'peak_multiplier_bps')::integer
            else peak_multiplier_bps
          end,
          weather_enabled = coalesce((d->>'weather_enabled')::boolean, weather_enabled),
          weather_surcharge = case
            when jsonb_typeof(d->'weather_surcharge') = 'number'
                 and (d->>'weather_surcharge')::integer between 0 and 200000
              then (d->>'weather_surcharge')::integer
            else weather_surcharge
          end,
          version = version + 1,
          updated_by = uid,
          updated_at = now()
      where active;

    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'pricing_surge_toggle', null, d);

    return public.delivery_admin_pricing('get', '{}'::jsonb);

  elsif p_action = 'reset_rules' then
    delete from public.delivery_cloud_pricing_rules;
    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'pricing_rules_reset', null, '{}'::jsonb);
    return public.delivery_admin_pricing('get', '{}'::jsonb);

  elsif p_action = 'save_geofence' then
    v_poly := d->'polygon';
    if jsonb_typeof(v_poly) is distinct from 'array' or jsonb_array_length(v_poly) not between 3 and 24 then
      raise sqlstate 'PT400' using message = 'Vùng đa giác cần từ 3 đến 24 đỉnh tọa độ trên bản đồ.';
    end if;
    for v_pt in select * from jsonb_array_elements(v_poly) loop
      if jsonb_typeof(v_pt) <> 'object'
         or jsonb_typeof(v_pt->'lat') <> 'number'
         or jsonb_typeof(v_pt->'lng') <> 'number' then
        raise sqlstate 'PT400' using message = 'Đỉnh tọa độ vùng Geofence không hợp lệ.';
      end if;
      v_lat := (v_pt->>'lat')::double precision;
      v_lng := (v_pt->>'lng')::double precision;
      if v_lat not between -90 and 90 or v_lng not between -180 and 180 then
        raise sqlstate 'PT400' using message = 'Tọa độ vùng Geofence ngoài phạm vi hợp lệ.';
      end if;
    end loop;

    if length(btrim(coalesce(d->>'name', ''))) not between 2 and 120 then
      raise sqlstate 'PT400' using message = 'Tên vùng phụ phí cần từ 2 đến 120 ký tự.';
    end if;

    v_id := coalesce(nullif(d->>'id', '')::uuid, gen_random_uuid());
    insert into public.delivery_cloud_geofences(
      id, name, zone_type, surcharge_fee, multiplier_bps, polygon, active, version, created_by, updated_at
    ) values (
      v_id,
      btrim(d->>'name'),
      case when coalesce(d->>'zone_type', 'surge') in ('surge', 'weather', 'restricted_surcharge', 'priority')
           then coalesce(d->>'zone_type', 'surge') else 'surge' end,
      greatest(0, least(500000, coalesce((d->>'surcharge_fee')::integer, 0))),
      greatest(10000, least(30000, coalesce((d->>'multiplier_bps')::integer, 10000))),
      v_poly,
      coalesce((d->>'active')::boolean, true),
      1,
      uid,
      now()
    )
    on conflict (id) do update set
      name = excluded.name,
      zone_type = excluded.zone_type,
      surcharge_fee = excluded.surcharge_fee,
      multiplier_bps = excluded.multiplier_bps,
      polygon = excluded.polygon,
      active = excluded.active,
      version = public.delivery_cloud_geofences.version + 1,
      updated_at = now()
    returning * into g;

    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'geofence_save', g.id, jsonb_build_object('name', g.name, 'surcharge_fee', g.surcharge_fee, 'active', g.active));

    return public.delivery_admin_pricing('get', '{}'::jsonb);

  elsif p_action = 'toggle_geofence' then
    v_id := (d->>'id')::uuid;
    update public.delivery_cloud_geofences
      set active = coalesce((d->>'active')::boolean, not active),
          version = version + 1,
          updated_at = now()
      where id = v_id
      returning * into g;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy vùng phụ phí Geofence.';
    end if;
    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'geofence_toggle', g.id, jsonb_build_object('active', g.active));
    return public.delivery_admin_pricing('get', '{}'::jsonb);

  elsif p_action = 'delete_geofence' then
    v_id := (d->>'id')::uuid;
    delete from public.delivery_cloud_geofences where id = v_id returning * into g;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy vùng phụ phí Geofence.';
    end if;
    update public.delivery_cloud_pricing
      set version = version + 1
      where id;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'geofence_delete', g.id, jsonb_build_object('name', g.name));
    return public.delivery_admin_pricing('get', '{}'::jsonb);

  else
    raise sqlstate 'PT400' using message = 'Thao tác bảng giá điều hành không hợp lệ.';
  end if;
end; $$;

revoke all on function public.delivery_admin_pricing(text, jsonb) from public, anon;
grant execute on function public.delivery_admin_pricing(text, jsonb) to authenticated;

-- Extend delivery_cloud_quote to apply dynamic pricing rules, peak/weather surge & polygon geofence surcharges
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
  max_weight := case when service = 'truck' then 500 else 30 end;
  if abs(lat1) > 90 or abs(lat2) > 90 or abs(lng1) > 180 or abs(lng2) > 180 or
     weight <= 0 or weight > max_weight or service is null or service not in ('standard','express','saving','same_day_2h','truck') then
    raise sqlstate 'PT400' using message = 'Tọa độ, dịch vụ hoặc khối lượng không hợp lệ.';
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
  if eff_weight > max_weight then raise sqlstate 'PT400' using message = 'Khối lượng quy đổi vượt giới hạn dịch vụ.'; end if;

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
  if p_details ? 'prefer_ev' then
    if jsonb_typeof(p_details->'prefer_ev') <> 'boolean' then raise sqlstate 'PT400' using message = 'Tùy chọn xe điện không hợp lệ.'; end if;
    prefer_ev := (p_details->>'prefer_ev')::boolean;
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
  fee := v_base + v_dist + v_weight + v_express + v_stop + v_round + v_ins + v_green + v_surge + v_geofence;

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
  ) || case
    when jsonb_array_length(v_matched_zones) > 0
      then jsonb_build_object('matched_geofences', v_matched_zones)
    else '{}'::jsonb
  end;
end; $$;

revoke all on function public.delivery_cloud_quote(jsonb) from public, anon;
grant execute on function public.delivery_cloud_quote(jsonb) to authenticated;

-- ============================================================================
-- PART 3: ORDER ENRICHMENT, SIGNATURE POD, BATCH COLUMNS & ORDER CREATION/TRANSITION
-- ============================================================================

alter table public.delivery_cloud_orders
  add column if not exists batch_group_id uuid;
alter table public.delivery_cloud_orders
  add column if not exists batch_sequence smallint;

alter table public.delivery_cloud_orders
  drop constraint if exists delivery_cloud_orders_batch_sequence_check;
alter table public.delivery_cloud_orders
  add constraint delivery_cloud_orders_batch_sequence_check
  check (batch_sequence is null or batch_sequence between 1 and 3);

create index if not exists delivery_cloud_orders_batch_idx
  on public.delivery_cloud_orders(batch_group_id, batch_sequence)
  where batch_group_id is not null;

-- Update delivery_cloud_order_enriched to distinguish photo POD vs touch signature & include masked phones
create or replace function public.delivery_cloud_order_enriched(o public.delivery_cloud_orders) returns jsonb
language sql stable security definer set search_path='' as $$
  select (to_jsonb(o) - 'request_payload' - 'request_key') || jsonb_build_object(
    'sender_profile', (
      select jsonb_build_object(
        'full_name', sa.full_name,
        'phone', sa.phone,
        'masked_phone', public.delivery_mask_phone(sa.phone)
      )
      from public.delivery_cloud_accounts sa
      where sa.user_id = o.owner_id
    ),
    'driver_profile', case
      when o.driver_id is null then null
      else (
        select jsonb_build_object(
          'user_id', da.user_id,
          'full_name', da.full_name,
          'phone', da.phone,
          'masked_phone', public.delivery_mask_phone(da.phone),
          'rating_avg', coalesce((
            select round(avg(pr.rating)::numeric, 2)
            from public.delivery_partner_reviews pr
            where pr.target_kind = 'driver' and pr.driver_id = da.user_id and not pr.hidden
          ), 0),
          'rating_count', (
            select count(*)::integer
            from public.delivery_partner_reviews pr
            where pr.target_kind = 'driver' and pr.driver_id = da.user_id and not pr.hidden
          )
        )
        from public.delivery_cloud_accounts da
        where da.user_id = o.driver_id
      )
    end,
    'recipient_masked_phone', public.delivery_mask_phone(o.details->>'recipient_phone'),
    'has_pod', exists (
      select 1 from public.delivery_live_events ev
      where ev.room_id = o.tracking_code
        and ev.kind = 'pod'
        and coalesce(ev.payload->>'evidence_type', 'photo') = 'photo'
    ),
    'pod_photo_path', (
      select ev.payload->>'path'
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code
        and ev.kind = 'pod'
        and coalesce(ev.payload->>'evidence_type', 'photo') = 'photo'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'has_signature', exists (
      select 1 from public.delivery_live_events ev
      where ev.room_id = o.tracking_code
        and ev.kind = 'pod'
        and ev.payload->>'evidence_type' = 'signature'
    ),
    'signature_path', (
      select ev.payload->>'path'
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code
        and ev.kind = 'pod'
        and ev.payload->>'evidence_type' = 'signature'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'recipient_signer_name', (
      select ev.payload->>'signer_name'
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code
        and ev.kind = 'pod'
        and ev.payload->>'evidence_type' = 'signature'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'latest_gps', (
      select ev.payload || jsonb_build_object('updated_at', ev.created_at)
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code and ev.kind = 'gps'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'driver_review', (
      select jsonb_build_object(
        'id', pr.id,
        'rating', pr.rating,
        'body', pr.body,
        'reply', pr.reply,
        'replied_at', pr.replied_at,
        'created_at', pr.created_at
      )
      from public.delivery_partner_reviews pr
      where pr.target_kind = 'driver' and pr.cloud_order_id = o.id and not pr.hidden
      order by pr.created_at desc
      limit 1
    ),
    'completed_checkpoints', coalesce(o.details->'completed_checkpoints', '[]'::jsonb)
  );
$$;

revoke all on function public.delivery_cloud_order_enriched(public.delivery_cloud_orders) from public, anon, authenticated;

-- Allow require_signature in delivery_cloud_create
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
    'require_signature','use_coins'
  ] <> '{}'::jsonb then
    raise sqlstate 'PT400' using message = 'Đơn hàng có trường không hỗ trợ hoặc quá dài.';
  end if;

  if coalesce((p_details->>'use_coins')::boolean, false) then
    perform 1 from public.delivery_market_coin_wallets where user_id = auth.uid() for update;
  end if;

  q := public.delivery_cloud_quote(p_details);
  v_coin_disc := coalesce((q->>'coin_discount')::integer, 0);
  v_payable := coalesce((q->>'payable_fee')::integer, (q->>'shipping_fee')::integer);

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
    auth.uid(), merchant, p_request_key, saved, p_details, (q->>'distance_meters')::integer,
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

-- Update delivery_cloud_list queue details to expose require_signature & estimated_earning
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
-- PART 4: REAL-TIME GPS PROXIMITY AUTO-DISPATCH, 28S EXCLUSIVE OFFER & BATCHING
-- ============================================================================

create table if not exists public.delivery_driver_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_online boolean not null default false,
  latitude double precision not null default 10.7769 check (latitude between -90 and 90),
  longitude double precision not null default 106.7009 check (longitude between -180 and 180),
  heading double precision not null default 0 check (heading between -360 and 360),
  vehicle_type text not null default 'motorbike' check (vehicle_type in ('motorbike', 'ev_scooter', 'truck')),
  allow_batching boolean not null default true,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists delivery_driver_presence_online_idx
  on public.delivery_driver_presence(is_online, last_seen_at desc);

create table if not exists public.delivery_driver_offers (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.delivery_cloud_orders(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  state text not null default 'pending' check (state in ('pending', 'accepted', 'rejected', 'expired', 'cancelled')),
  distance_meters integer not null default 0 check (distance_meters >= 0),
  radius_tier_km smallint not null default 3 check (radius_tier_km in (3, 5, 8)),
  estimated_earning bigint not null default 0 check (estimated_earning >= 0),
  score numeric(8,2) not null default 0,
  expires_at timestamptz not null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists delivery_driver_offers_driver_idx
  on public.delivery_driver_offers(driver_id, state, expires_at desc);
create index if not exists delivery_driver_offers_order_idx
  on public.delivery_driver_offers(order_id, state, expires_at desc);

alter table public.delivery_driver_presence enable row level security;
alter table public.delivery_driver_offers enable row level security;

revoke all on table
  public.delivery_driver_presence,
  public.delivery_driver_offers
from public, anon, authenticated;

-- Internal proximity matcher: expands 3km -> 5km -> 8km and creates an exclusive 28s offer
create or replace function public.delivery_match_driver_offer_for_order(p_order_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  v_existing uuid;
  v_pickup_lat double precision;
  v_pickup_lng double precision;
  v_service text;
  v_prefer_ev boolean;
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
      and (
        (v_service = 'truck' and dp.vehicle_type = 'truck')
        or (v_service <> 'truck' and dp.vehicle_type in ('motorbike', 'ev_scooter'))
      )
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

-- Trigger auto-dispatch offer matching whenever an order enters/becomes ready in 'searching'
create or replace function public.delivery_cloud_orders_auto_offer_trg_fn() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status = 'searching' and new.merchant_ready and new.driver_id is null and new.fulfillment_provider is null then
    if tg_op = 'INSERT' or not coalesce(old.merchant_ready, false) or old.status is distinct from 'searching' then
      perform public.delivery_match_driver_offer_for_order(new.id);
    end if;
  elsif tg_op = 'UPDATE' and (new.status <> 'searching' or new.driver_id is not null) then
    update public.delivery_driver_offers
      set state = case when state = 'pending' and driver_id = new.driver_id then 'accepted' else 'cancelled' end,
          responded_at = coalesce(responded_at, now())
      where order_id = new.id and state = 'pending';
  end if;
  return new;
end; $$;

revoke all on function public.delivery_cloud_orders_auto_offer_trg_fn() from public, anon, authenticated;

drop trigger if exists delivery_cloud_orders_auto_offer_trg on public.delivery_cloud_orders;
create trigger delivery_cloud_orders_auto_offer_trg
  after insert or update of status, merchant_ready, driver_id on public.delivery_cloud_orders
  for each row execute function public.delivery_cloud_orders_auto_offer_trg_fn();

-- Update delivery_cloud_transition to enforce require_signature + photo-only require_pod
create or replace function public.delivery_cloud_transition(
  p_order uuid,
  p_action text,
  p_version integer,
  p_request_key uuid,
  p_reason text default ''
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  a public.delivery_cloud_accounts;
  op boolean;
  next_status text;
  request jsonb;
  prior public.delivery_cloud_commands;
  response jsonb;
  secret public.delivery_cloud_order_secrets;
  candidate_otp text;
  history_reason text := btrim(coalesce(p_reason, ''));
  v_pay_method text;
  need_fee boolean := false;
  need_cod boolean := false;
  v_fee_now integer := 0;
  v_cod_now integer := 0;
begin
  if auth.uid() is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  op := public.delivery_is_operator();
  if not op and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa có hồ sơ hoặc đang khóa.';
  end if;
  if p_request_key is null then
    raise sqlstate 'PT400' using message = 'Thiếu mã yêu cầu.';
  end if;
  if p_action is null
     or p_action not in (
       'ready','claim','cancel','arrive','pickup','deliver',
       'fail','retry','return','complete_return','collect_cash'
     )
     or p_reason is null
     or length(p_reason) > 500 then
    raise sqlstate 'PT400' using message = 'Thao tác hoặc lý do không hợp lệ.';
  end if;
  if p_action in ('cancel','fail','return') and length(btrim(p_reason)) < 3 then
    raise sqlstate 'PT400' using message = 'Cần nhập lý do ít nhất 3 ký tự.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_key::text, 0));
  request := jsonb_build_object(
    'order', p_order,
    'action', p_action,
    'version', p_version,
    'reason', case when p_action = 'deliver' and p_reason ~ '^(OTP:)?[0-9]{6}$' then 'OTP_SUBMITTED' else p_reason end
  );
  select * into prior
    from public.delivery_cloud_commands
    where actor_id = auth.uid() and request_key = p_request_key;
  if found then
    if prior.request_payload <> request then
      raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.';
    end if;
    return prior.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('driver:' || auth.uid()::text, 0));
  select * into o from public.delivery_cloud_orders where id = p_order for update;
  select * into a from public.delivery_cloud_accounts where user_id = auth.uid();

  if o.id is null or (
    not op
    and auth.uid() not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))
    and not (
      p_action = 'claim'
      and public.delivery_cloud_has_membership(a.user_id, 'driver')
      and o.status = 'searching'
      and o.merchant_ready
    )
  ) then
    raise sqlstate 'PT404' using message = 'Không tìm thấy đơn hàng được phép truy cập.';
  end if;

  if p_version is distinct from o.version then
    raise sqlstate 'PT409' using message = 'Đơn đã thay đổi. Vui lòng tải lại.';
  end if;

  next_status := o.status;

  if p_action = 'ready' then
    if (not op and auth.uid() is distinct from o.merchant_id) or o.status <> 'searching' or o.merchant_ready then
      raise sqlstate 'PT409' using message = 'Không thể xác nhận cửa hàng sẵn sàng.';
    end if;
    o.merchant_ready := true;

  elsif p_action = 'claim' then
    if not public.delivery_cloud_has_membership(a.user_id, 'driver')
       or a.blocked
       or o.status <> 'searching'
       or not o.merchant_ready
       or o.driver_id is not null then
      raise sqlstate 'PT409' using message = 'Đơn không còn khả dụng hoặc tài khoản chưa được duyệt tài xế.';
    end if;
    if exists (
      select 1 from public.delivery_cloud_orders
      where driver_id = auth.uid() and status not in ('delivered','returned','cancelled')
    ) then
      raise sqlstate 'PT409' using message = 'Bạn đang có chuyến chưa hoàn tất.';
    end if;
    o.driver_id := auth.uid();
    next_status := 'accepted';

  elsif p_action = 'cancel' then
    if (not op and auth.uid() is distinct from o.owner_id and auth.uid() is distinct from o.merchant_id)
       or o.status not in ('searching','accepted','arrivingPickup')
       or length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then
      raise sqlstate 'PT409' using message = 'Không thể hủy đơn hoặc chưa nhập lý do hợp lệ.';
    end if;
    next_status := 'cancelled';
    o.cancel_reason := btrim(p_reason);

  elsif p_action = 'collect_cash' then
    if not op and (
      auth.uid() is distinct from o.driver_id
      or not public.delivery_cloud_has_membership(auth.uid(), 'driver')
      or coalesce(a.blocked, true)
    ) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến hoặc quản trị viên được xác nhận thu tiền mặt.';
    end if;
    if o.fulfillment_provider is not null then
      raise sqlstate 'PT409' using message = 'Đơn gửi qua hãng vận chuyển ngoài không thu tiền mặt nội bộ.';
    end if;
    if o.payment_status = 'REVIEW' or exists (
      select 1 from public.delivery_payment_transactions
      where order_id = o.id and status in ('CREATING','PENDING','REVIEW')
    ) then
      raise sqlstate 'PT409' using message = 'Đơn đang có giao dịch thanh toán trực tuyến chờ xử lý hoặc cần đối soát.';
    end if;

    v_pay_method := coalesce(o.details->>'payment_method', 'sender_cash');
    need_fee := (
      o.payment_status = 'UNPAID'
      and o.payable_fee > 0
      and o.cash_collected_fee = 0
      and (
        (v_pay_method = 'sender_cash' and o.status in ('arrivingPickup','inTransit','delivered'))
        or (v_pay_method = 'recipient_cash' and o.status in ('inTransit','delivered'))
      )
    );
    need_cod := (
      o.cod_amount > 0
      and o.cash_collected_cod < o.cod_amount
      and o.status in ('inTransit','delivered')
    );

    if not need_fee and not need_cod then
      raise sqlstate 'PT409' using message = 'Đơn hàng không còn khoản tiền mặt cần xác nhận thu.';
    end if;

    v_fee_now := case when need_fee then o.payable_fee else 0 end;
    v_cod_now := case when need_cod then (o.cod_amount - o.cash_collected_cod) else 0 end;

    if need_fee then
      o.cash_collected_fee := o.payable_fee;
      o.payment_status := 'PAID';
    end if;
    if need_cod then
      o.cash_collected_cod := o.cod_amount;
    end if;
    o.cash_collected_at := now();
    o.cash_collected_by := auth.uid();

    history_reason := case
      when v_fee_now > 0 and v_cod_now > 0 then
        'Đã thu tiền mặt cước ' || v_fee_now || ' đ và COD ' || v_cod_now || ' đ'
      when v_fee_now > 0 then
        'Đã thu tiền mặt cước ' || v_fee_now || ' đ'
      else
        'Đã thu tiền mặt COD ' || v_cod_now || ' đ'
    end || case
      when length(history_reason) > 0 then ' · ' || left(history_reason, 200)
      else ''
    end;

  else
    if not op and (auth.uid() is distinct from o.driver_id or not public.delivery_cloud_has_membership(auth.uid(), 'driver')) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến hoặc quản trị viên được cập nhật.';
    end if;
    next_status := case
      when p_action = 'arrive' and o.status = 'accepted' then 'arrivingPickup'
      when p_action = 'pickup' and o.status = 'arrivingPickup' then 'inTransit'
      when p_action = 'deliver' and o.status = 'inTransit' then 'delivered'
      when p_action = 'fail' and o.status = 'inTransit' then 'failed'
      when p_action = 'retry' and o.status = 'failed' then 'inTransit'
      when p_action = 'return' and o.status = 'failed' then 'returning'
      when p_action = 'complete_return' and o.status = 'returning' then 'returned'
    end;
    if next_status is null then
      raise sqlstate 'PT409' using message = 'Thao tác không phù hợp trạng thái đơn.';
    end if;
    if p_action = 'deliver' and not op then
      if coalesce((o.details->>'require_pod')::boolean, false) and not exists (
        select 1 from public.delivery_live_events
        where room_id = o.tracking_code
          and kind = 'pod'
          and coalesce(payload->>'evidence_type', 'photo') = 'photo'
      ) then
        raise sqlstate 'PT409' using message = 'Cần tải ảnh bằng chứng giao hàng trước khi hoàn tất.';
      end if;
      if coalesce((o.details->>'require_signature')::boolean, false) and not exists (
        select 1 from public.delivery_live_events
        where room_id = o.tracking_code
          and kind = 'pod'
          and payload->>'evidence_type' = 'signature'
      ) then
        raise sqlstate 'PT409' using message = 'Cần chữ ký điện tử người nhận trước khi hoàn tất giao hàng.';
      end if;
      select * into secret from public.delivery_cloud_order_secrets where order_id = o.id for update;
      if found and secret.verified_at is null then
        candidate_otp := substring(btrim(p_reason) from '([0-9]{6})');
        if candidate_otp is null or encode(sha256(convert_to(candidate_otp, 'UTF8')), 'hex') <> secret.otp_hash then
          update public.delivery_cloud_order_secrets set attempts = attempts + 1 where order_id = o.id;
          raise sqlstate 'PT409' using message = 'Cần mã OTP 6 số hợp lệ từ người nhận để hoàn tất giao hàng.';
        end if;
        update public.delivery_cloud_order_secrets set verified_at = now(), attempts = attempts + 1 where order_id = o.id;
        history_reason := 'Đã xác thực OTP người nhận';
      end if;
    elsif p_action = 'deliver' and history_reason ~ '^(OTP:)?[0-9]{6}$' then
      history_reason := 'Đã xác thực giao hàng';
    end if;
  end if;

  update public.delivery_cloud_orders set
    status = next_status,
    driver_id = o.driver_id,
    merchant_ready = o.merchant_ready,
    cancel_reason = o.cancel_reason,
    payment_status = o.payment_status,
    cash_collected_fee = o.cash_collected_fee,
    cash_collected_cod = o.cash_collected_cod,
    cash_collected_at = o.cash_collected_at,
    cash_collected_by = o.cash_collected_by,
    version = version + 1,
    updated_at = now()
  where id = o.id returning * into o;

  if p_action = 'claim' then
    insert into public.delivery_live_members values (o.tracking_code, auth.uid(), 'driver')
      on conflict (room_id, user_id) do update set role = 'driver';
  end if;

  insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
    values (o.id, auth.uid(), p_action, o.status, o.version, history_reason);
  insert into public.delivery_live_events(room_id, kind, payload)
    values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));

  response := public.delivery_cloud_order_enriched(o);
  insert into public.delivery_cloud_commands values (auth.uid(), p_request_key, request, response, now());
  return response;
end; $$;

revoke all on function public.delivery_cloud_transition(uuid, text, integer, uuid, text) from public, anon;
grant execute on function public.delivery_cloud_transition(uuid, text, integer, uuid, text) to authenticated;

-- Driver Dispatch RPC: Online/Offline GPS Presence, 28s Exclusive Offer & Multi-Order Route Batching
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

  select count(*)::integer into v_active_count
    from public.delivery_cloud_orders
    where driver_id = uid and status not in ('delivered', 'returned', 'cancelled');

  if p_action = 'get_presence' then
    return jsonb_build_object(
      'presence', to_jsonb(dp),
      'active_trips_count', v_active_count,
      'server_now', now()
    );

  elsif p_action = 'set_presence' then
    v_online := coalesce((d->>'is_online')::boolean, dp.is_online);
    v_lat := coalesce((d->>'latitude')::double precision, dp.latitude);
    v_lng := coalesce((d->>'longitude')::double precision, dp.longitude);
    v_heading := coalesce((d->>'heading')::double precision, dp.heading);
    v_vehicle := coalesce(nullif(d->>'vehicle_type', ''), dp.vehicle_type);
    v_batching := coalesce((d->>'allow_batching')::boolean, dp.allow_batching);

    if v_lat not between -90 and 90 or v_lng not between -180 and 180 or v_heading not between -360 and 360 then
      raise sqlstate 'PT400' using message = 'Tọa độ định vị tài xế không hợp lệ.';
    end if;
    if v_vehicle not in ('motorbike', 'ev_scooter', 'truck') then
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
      'presence', to_jsonb(dp),
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
         or coalesce((o.details->>'is_round_trip')::boolean, false) then
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

commit;
