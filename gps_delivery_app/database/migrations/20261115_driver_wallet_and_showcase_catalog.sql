-- Additive migration: Driver Cloud Wallet (80/20 settlement split, VietQR escrow deposit,
-- bank withdrawal & operator dual-step approval) + Virtual Showcase Food, Beverage & Store Catalog.
-- Safe to reapply; seeds zero demo rows automatically during migration (clean-start preserved).
begin;

-- ============================================================================
-- PART 1: DRIVER CLOUD WALLET, 80/20 REVENUE SPLIT & DEPOSIT/WITHDRAWAL LEDGER
-- ============================================================================

create table if not exists public.delivery_driver_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null default 0,
  locked_balance bigint not null default 0 check (locked_balance >= 0),
  total_earned bigint not null default 0 check (total_earned >= 0),
  total_commission bigint not null default 0 check (total_commission >= 0),
  total_topup bigint not null default 0 check (total_topup >= 0),
  total_withdrawn bigint not null default 0 check (total_withdrawn >= 0),
  escrow_target integer not null default 200000 check (escrow_target between 0 and 10000000),
  bank_bin text not null default '' check (bank_bin = '' or bank_bin ~ '^[0-9]{6}$'),
  bank_name text not null default '' check (length(bank_name) <= 120),
  bank_account_no text not null default '' check (bank_account_no = '' or bank_account_no ~ '^[0-9A-Za-z]{6,24}$'),
  bank_account_name text not null default '' check (length(bank_account_name) <= 120),
  version integer not null default 1 check (version >= 1),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_driver_wallet_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('topup', 'withdraw')),
  amount integer not null check (amount between 50000 and 50000000),
  state text not null default 'pending' check (state in ('pending', 'approved', 'rejected', 'cancelled')),
  transfer_code text not null check (length(transfer_code) between 4 and 40),
  bank_bin text not null default '' check (bank_bin = '' or bank_bin ~ '^[0-9]{6}$'),
  bank_name text not null default '' check (length(bank_name) <= 120),
  bank_account_no text not null default '' check (bank_account_no = '' or bank_account_no ~ '^[0-9A-Za-z]{6,24}$'),
  bank_account_name text not null default '' check (length(bank_account_name) <= 120),
  driver_note text not null default '' check (length(driver_note) <= 300),
  admin_note text not null default '' check (length(admin_note) <= 500),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  request_key uuid not null,
  version integer not null default 1 check (version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, request_key)
);

create index if not exists delivery_driver_wallet_requests_user_idx
  on public.delivery_driver_wallet_requests(user_id, created_at desc, id desc);
create index if not exists delivery_driver_wallet_requests_state_idx
  on public.delivery_driver_wallet_requests(state, created_at desc, id desc);

create table if not exists public.delivery_driver_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta bigint not null,
  balance_after bigint not null,
  kind text not null check (kind in (
    'trip_earning_80',
    'trip_cash_fee_deduct',
    'topup_approved',
    'withdraw_lock',
    'withdraw_unlock_cancel',
    'withdraw_unlock_reject',
    'withdraw_completed',
    'operator_adjust'
  )),
  order_id uuid references public.delivery_cloud_orders(id) on delete set null,
  request_id uuid references public.delivery_driver_wallet_requests(id) on delete set null,
  note text not null default '' check (length(note) <= 500),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists delivery_driver_wallet_ledger_user_idx
  on public.delivery_driver_wallet_ledger(user_id, created_at desc, id desc);
create index if not exists delivery_driver_wallet_ledger_order_idx
  on public.delivery_driver_wallet_ledger(order_id, kind);

drop trigger if exists delivery_driver_wallet_ledger_immutable on public.delivery_driver_wallet_ledger;
create trigger delivery_driver_wallet_ledger_immutable
  before update or delete on public.delivery_driver_wallet_ledger
  for each row execute function public.delivery_market_immutable();

alter table public.delivery_driver_wallets enable row level security;
alter table public.delivery_driver_wallet_requests enable row level security;
alter table public.delivery_driver_wallet_ledger enable row level security;

revoke all on table
  public.delivery_driver_wallets,
  public.delivery_driver_wallet_requests,
  public.delivery_driver_wallet_ledger
from public, anon, authenticated;

-- Idempotent 80/20 settlement sync for delivered internal driver orders
create or replace function public.delivery_driver_wallet_sync_order(
  p_order_id uuid,
  p_notify boolean default true
) returns void
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  w public.delivery_driver_wallets;
  v_gross bigint := 0;
  v_driver_share bigint := 0;
  v_commission bigint := 0;
  v_posted_earn bigint := 0;
  v_posted_deduct bigint := 0;
  v_deduct_delta bigint := 0;
  v_earned_now boolean := false;
begin
  if p_order_id is null then return; end if;
  select * into o from public.delivery_cloud_orders where id = p_order_id;
  if not found or o.driver_id is null or o.fulfillment_provider is not null or o.status <> 'delivered' then
    return;
  end if;

  insert into public.delivery_driver_wallets(user_id)
    values (o.driver_id)
    on conflict (user_id) do nothing;
  select * into w from public.delivery_driver_wallets where user_id = o.driver_id for update;

  v_gross := greatest(0, o.shipping_fee)::bigint;
  v_driver_share := round(v_gross * 0.80)::bigint;
  v_commission := greatest(0, v_gross - v_driver_share);

  select coalesce(sum(delta), 0) into v_posted_earn
    from public.delivery_driver_wallet_ledger
    where user_id = o.driver_id and order_id = o.id and kind = 'trip_earning_80';

  if v_driver_share > v_posted_earn then
    update public.delivery_driver_wallets
      set balance = balance + (v_driver_share - v_posted_earn),
          total_earned = total_earned + (v_driver_share - v_posted_earn),
          total_commission = total_commission + v_commission,
          version = version + 1,
          updated_at = now()
      where user_id = o.driver_id
      returning * into w;

    insert into public.delivery_driver_wallet_ledger(
      user_id, delta, balance_after, kind, order_id, note, metadata
    ) values (
      o.driver_id,
      v_driver_share - v_posted_earn,
      w.balance,
      'trip_earning_80',
      o.id,
      'Thu nhập 80% cước vận đơn ' || o.tracking_code || ' (Chiết khấu sàn 20%: ' || v_commission || ' đ)',
      jsonb_build_object(
        'tracking_code', o.tracking_code,
        'shipping_fee', o.shipping_fee,
        'driver_share_80', v_driver_share,
        'platform_commission_20', v_commission
      )
    );
    v_earned_now := true;
  end if;

  select coalesce(sum(-delta), 0) into v_posted_deduct
    from public.delivery_driver_wallet_ledger
    where user_id = o.driver_id and order_id = o.id and kind = 'trip_cash_fee_deduct';

  v_deduct_delta := greatest(0, o.cash_collected_fee::bigint - v_posted_deduct);
  if v_deduct_delta > 0 then
    update public.delivery_driver_wallets
      set balance = balance - v_deduct_delta,
          version = version + 1,
          updated_at = now()
      where user_id = o.driver_id
      returning * into w;

    insert into public.delivery_driver_wallet_ledger(
      user_id, delta, balance_after, kind, order_id, note, metadata
    ) values (
      o.driver_id,
      -v_deduct_delta,
      w.balance,
      'trip_cash_fee_deduct',
      o.id,
      'Khấu trừ tiền mặt cước đã thu trực tiếp vận đơn ' || o.tracking_code,
      jsonb_build_object(
        'tracking_code', o.tracking_code,
        'cash_collected_fee', o.cash_collected_fee,
        'deducted_now', v_deduct_delta
      )
    );
  end if;

  if p_notify and v_earned_now then
    perform public.delivery_emit_notification(
      o.driver_id,
      'shipping',
      'driver_wallet_earning',
      'Cộng thu nhập chuyến ' || o.tracking_code,
      'Ví Tài xế đã ghi nhận +' || v_driver_share || ' đ (80% cước)' ||
        case when o.cash_collected_fee > 0
             then ', đối trừ ' || o.cash_collected_fee || ' đ tiền mặt cước đã thu.'
             else ' từ đơn thanh toán trực tuyến.' end,
      'cloud_order',
      o.id,
      jsonb_build_object(
        'tracking_code', o.tracking_code,
        'driver_share', v_driver_share,
        'platform_commission', v_commission,
        'cash_collected_fee', o.cash_collected_fee,
        'wallet_balance', w.balance
      )
    );
  end if;
end; $$;

revoke all on function public.delivery_driver_wallet_sync_order(uuid, boolean) from public, anon, authenticated;

-- Hook 80/20 Driver Wallet settlement into delivery_cloud_orders_after_change trigger
create or replace function public.delivery_cloud_orders_after_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  is_market_linked boolean := false;
  v_earn bigint := 0;
  v_title text;
  v_body text;
  v_pay_body text;
  v_meta jsonb;
  v_fee_delta integer := 0;
  v_cod_delta integer := 0;
  rcp uuid;
begin
  is_market_linked := exists (
    select 1 from public.delivery_market_shop_orders where delivery_id = new.id
  ) or exists (
    select 1 from public.delivery_market_shipments where delivery_id = new.id
  );

  v_meta := jsonb_build_object(
    'tracking_code', new.tracking_code,
    'status', new.status,
    'payment_status', new.payment_status,
    'shipping_fee', new.shipping_fee,
    'coin_discount', new.coin_discount,
    'payable_fee', new.payable_fee,
    'cash_collected_fee', new.cash_collected_fee,
    'cash_collected_cod', new.cash_collected_cod
  );

  if tg_op = 'INSERT' then
    if new.merchant_id is not null and new.merchant_id is distinct from new.owner_id
       and new.merchant_id is distinct from actor and not new.merchant_ready then
      perform public.delivery_emit_notification(
        new.merchant_id, 'shipping', 'merchant_prepare',
        'Đơn gửi hàng mới chờ chuẩn bị',
        'Vận đơn ' || new.tracking_code || ' đang chờ cửa hàng xác nhận sẵn sàng bàn giao.',
        'cloud_order', new.id, v_meta
      );
    end if;
    return new;
  end if;

  if new.driver_id is not null and new.fulfillment_provider is null and new.status = 'delivered'
     and (old.status is distinct from 'delivered' or new.cash_collected_fee is distinct from old.cash_collected_fee) then
    perform public.delivery_driver_wallet_sync_order(new.id, true);
  end if;

  if not is_market_linked and new.coin_discount > 0
     and new.status in ('cancelled', 'returned')
     and old.status not in ('cancelled', 'returned') then
    if not exists (
      select 1 from public.delivery_market_coin_ledger
      where user_id = new.owner_id and kind = 'release_shipping_cancel' and reference_id = new.id
    ) then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values (new.owner_id, new.coin_discount)
        on conflict (user_id) do update
          set balance = public.delivery_market_coin_wallets.balance + excluded.balance,
              updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values (new.owner_id, new.coin_discount, 'release_shipping_cancel', new.id);
      perform public.delivery_emit_notification(
        new.owner_id, 'promo', 'release_shipping_cancel',
        'Hoàn lại Xu cước vận chuyển',
        'Đã hoàn +' || new.coin_discount || ' Xu vào Ví Xu từ vận đơn ' || new.tracking_code || '.',
        'cloud_order', new.id, v_meta || jsonb_build_object('coins_delta', new.coin_discount)
      );
    end if;
  end if;

  if not is_market_linked and new.status = 'delivered' and old.status is distinct from 'delivered' then
    v_earn := floor(greatest(0, new.payable_fee) * 0.01)::bigint;
    if v_earn > 0 and not exists (
      select 1 from public.delivery_market_coin_ledger
      where user_id = new.owner_id and kind = 'earn_shipping' and reference_id = new.id
    ) then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values (new.owner_id, v_earn)
        on conflict (user_id) do update
          set balance = public.delivery_market_coin_wallets.balance + excluded.balance,
              updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values (new.owner_id, v_earn, 'earn_shipping', new.id);
      perform public.delivery_emit_notification(
        new.owner_id, 'promo', 'earn_shipping',
        'Tích lũy Xu giao hàng thành công',
        'Bạn nhận được +' || v_earn || ' Xu thưởng từ vận đơn ' || new.tracking_code || '.',
        'cloud_order', new.id, v_meta || jsonb_build_object('coins_delta', v_earn)
      );
    end if;
  end if;

  v_fee_delta := greatest(0, new.cash_collected_fee - coalesce(old.cash_collected_fee, 0));
  v_cod_delta := greatest(0, new.cash_collected_cod - coalesce(old.cash_collected_cod, 0));
  if v_fee_delta > 0 or v_cod_delta > 0 then
    v_pay_body := case
      when v_fee_delta > 0 and v_cod_delta > 0 then
        'Tài xế đã xác nhận thu tiền mặt cước ' || v_fee_delta || ' đ và COD ' || v_cod_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
      when v_fee_delta > 0 then
        'Tài xế đã xác nhận thu tiền mặt cước ' || v_fee_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
      else
        'Tài xế đã xác nhận thu hộ COD ' || v_cod_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
    end;
    for rcp in
      select distinct u_id
      from unnest(array[new.owner_id, new.merchant_id]) as u_id
      where u_id is not null and u_id is distinct from actor
    loop
      perform public.delivery_emit_notification(
        rcp, 'shipping', 'cash_collected',
        'Đã xác nhận thu tiền mặt',
        v_pay_body, 'cloud_order', new.id, v_meta
      );
    end loop;
  elsif new.payment_status = 'PAID'
        and old.payment_status is distinct from 'PAID'
        and new.cash_collected_fee = coalesce(old.cash_collected_fee, 0) then
    for rcp in
      select distinct u_id
      from unnest(array[new.owner_id, new.merchant_id]) as u_id
      where u_id is not null and u_id is distinct from actor
    loop
      perform public.delivery_emit_notification(
        rcp, 'shipping', 'payment_paid',
        'Thanh toán cước trực tuyến thành công',
        'Vận đơn ' || new.tracking_code || ' đã ghi nhận thanh toán cước ' || new.payable_fee || ' đ.',
        'cloud_order', new.id, v_meta
      );
    end loop;
  end if;

  if new.merchant_ready and not old.merchant_ready and new.owner_id is distinct from actor then
    perform public.delivery_emit_notification(
      new.owner_id, 'shipping', 'merchant_ready',
      'Cửa hàng đã sẵn sàng giao kiện',
      'Vận đơn ' || new.tracking_code || ' đã sẵn sàng và đang tìm tài xế nhận chuyến.',
      'cloud_order', new.id, v_meta
    );
  end if;

  if new.status is distinct from old.status then
    case new.status
      when 'accepted' then
        v_title := 'Tài xế đã nhận vận đơn';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã có tài xế tiếp nhận và đang di chuyển lấy hàng.';
      when 'arrivingPickup' then
        v_title := 'Tài xế đã tới điểm lấy hàng';
        v_body := 'Tài xế đang làm thủ tục nhận kiện hàng ' || new.tracking_code || '.';
      when 'inTransit' then
        v_title := 'Đơn hàng đang trên đường giao';
        v_body := 'Tài xế đã nhận kiện và đang giao vận đơn ' || new.tracking_code || ' tới người nhận.';
      when 'delivered' then
        v_title := 'Giao hàng thành công';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã giao hoàn tất cho người nhận.';
      when 'failed' then
        v_title := 'Giao hàng tạm hoãn';
        v_body := 'Vận đơn ' || new.tracking_code || ' chưa giao được, vui lòng kiểm tra chi tiết hành trình.';
      when 'returning' then
        v_title := 'Đơn hàng đang chuyển hoàn';
        v_body := 'Vận đơn ' || new.tracking_code || ' đang được tài xế hoàn trả về điểm gửi.';
      when 'returned' then
        v_title := 'Đã hoàn trả kiện hàng';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã bàn giao hoàn trả thành công.';
      when 'cancelled' then
        v_title := 'Vận đơn đã hủy';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã hủy'
          || case when length(btrim(coalesce(new.cancel_reason, ''))) > 0
                  then ': ' || left(btrim(new.cancel_reason), 180)
                  else '.' end;
      else
        v_title := null;
    end case;

    if v_title is not null then
      for rcp in
        select distinct u_id
        from unnest(array[new.owner_id, new.merchant_id, case when new.status = 'cancelled' then old.driver_id else null end]) as u_id
        where u_id is not null and u_id is distinct from actor
      loop
        perform public.delivery_emit_notification(
          rcp, 'shipping', 'order_' || new.status,
          v_title, v_body, 'cloud_order', new.id, v_meta
        );
      end loop;
    end if;
  end if;

  return new;
end; $$;

revoke all on function public.delivery_cloud_orders_after_change() from public, anon, authenticated;

-- Silent backfill for any existing delivered driver trips (0 rows on clean start)
do $$
declare
  r record;
begin
  for r in
    select id from public.delivery_cloud_orders
    where status = 'delivered' and driver_id is not null and fulfillment_provider is null
    order by updated_at asc, id asc
  loop
    perform public.delivery_driver_wallet_sync_order(r.id, false);
  end loop;
end $$;

-- Authoritative Driver Cloud Wallet RPC
create or replace function public.delivery_driver_wallet(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  a public.delivery_cloud_accounts;
  w public.delivery_driver_wallets;
  req public.delivery_driver_wallet_requests;
  v_target_user uuid;
  v_amount integer;
  v_req_key uuid;
  v_req_id uuid;
  v_bin text;
  v_bank text;
  v_acc_no text;
  v_acc_name text;
  v_note text;
  v_decision text;
  v_state_filter text;
  v_kind_filter text;
  v_cod_holding bigint := 0;
  v_trips_settled integer := 0;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id = uid for share;
  if a.blocked or (a.user_id is null and not op) then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa kích hoạt hoặc đang tạm khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000 then
    raise sqlstate 'PT400' using message = 'Dữ liệu ví tài xế không hợp lệ.';
  end if;

  if p_action in ('admin_list', 'admin_resolve') then
    if not op then
      raise sqlstate 'PT403' using message = 'Cần quyền điều hành viên để duyệt ví tài xế.';
    end if;

    if p_action = 'admin_list' then
      v_state_filter := coalesce(d->>'state', 'all');
      v_kind_filter := coalesce(d->>'kind', 'all');
      if v_state_filter not in ('all', 'pending', 'approved', 'rejected', 'cancelled')
         or v_kind_filter not in ('all', 'topup', 'withdraw') then
        raise sqlstate 'PT400' using message = 'Bộ lọc yêu cầu ví không hợp lệ.';
      end if;

      return jsonb_build_object(
        'kpis', jsonb_build_object(
          'pending_topups', (select count(*)::int from public.delivery_driver_wallet_requests where state = 'pending' and kind = 'topup'),
          'pending_withdrawals', (select count(*)::int from public.delivery_driver_wallet_requests where state = 'pending' and kind = 'withdraw'),
          'pending_withdraw_amount', coalesce((select sum(amount)::bigint from public.delivery_driver_wallet_requests where state = 'pending' and kind = 'withdraw'), 0),
          'approved_topup_total', coalesce((select sum(total_topup)::bigint from public.delivery_driver_wallets), 0),
          'approved_withdraw_total', coalesce((select sum(total_withdrawn)::bigint from public.delivery_driver_wallets), 0),
          'total_driver_balances', coalesce((select sum(balance)::bigint from public.delivery_driver_wallets), 0),
          'total_platform_commission', coalesce((select sum(total_commission)::bigint from public.delivery_driver_wallets), 0)
        ),
        'requests', coalesce((
          select jsonb_agg(to_jsonb(x) order by (x.state = 'pending') desc, x.created_at desc, x.id desc)
          from (
            select
              r.*,
              coalesce(da.full_name, 'Đối tác tài xế') as driver_name,
              coalesce(da.phone, '') as driver_phone,
              coalesce(dw.balance, 0) as driver_balance,
              coalesce(dw.locked_balance, 0) as driver_locked_balance
            from public.delivery_driver_wallet_requests r
            left join public.delivery_cloud_accounts da on da.user_id = r.user_id
            left join public.delivery_driver_wallets dw on dw.user_id = r.user_id
            where (v_state_filter = 'all' or r.state = v_state_filter)
              and (v_kind_filter = 'all' or r.kind = v_kind_filter)
            order by (r.state = 'pending') desc, r.created_at desc, r.id desc
            limit 60
          ) x
        ), '[]'::jsonb)
      );
    end if;

    if d - array['request_id', 'decision', 'admin_note'] <> '{}'::jsonb
       or jsonb_typeof(d->'request_id') is distinct from 'string'
       or jsonb_typeof(d->'decision') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Yêu cầu phê duyệt ví không hợp lệ.';
    end if;
    v_req_id := (d->>'request_id')::uuid;
    v_decision := d->>'decision';
    v_note := btrim(coalesce(d->>'admin_note', ''));
    if v_decision not in ('approve', 'reject') or length(v_note) not between 3 and 500 then
      raise sqlstate 'PT400' using message = 'Cần chọn quyết định hợp lệ và nhập ghi chú đối soát từ 3 ký tự.';
    end if;

    select * into req from public.delivery_driver_wallet_requests where id = v_req_id for update;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy yêu cầu nạp/rút ví tài xế.';
    end if;
    if req.state <> 'pending' then
      raise sqlstate 'PT409' using message = 'Yêu cầu này đã được xử lý trước đó.';
    end if;

    insert into public.delivery_driver_wallets(user_id)
      values (req.user_id)
      on conflict (user_id) do nothing;
    select * into w from public.delivery_driver_wallets where user_id = req.user_id for update;

    if req.kind = 'topup' then
      if v_decision = 'approve' then
        update public.delivery_driver_wallets
          set balance = balance + req.amount,
              total_topup = total_topup + req.amount,
              version = version + 1,
              updated_at = now()
          where user_id = req.user_id
          returning * into w;
        insert into public.delivery_driver_wallet_ledger(
          user_id, delta, balance_after, kind, request_id, note, metadata
        ) values (
          req.user_id, req.amount, w.balance, 'topup_approved', req.id,
          'Đã duyệt nạp ký quỹ ' || req.transfer_code || ' · ' || v_note,
          jsonb_build_object('transfer_code', req.transfer_code, 'amount', req.amount)
        );
        perform public.delivery_emit_notification(
          req.user_id, 'promo', 'driver_topup_approved',
          'Nạp ký quỹ thành công +' || req.amount || ' đ',
          'Yêu cầu nạp mã ' || req.transfer_code || ' đã được duyệt. Số dư khả dụng hiện tại: ' || w.balance || ' đ.',
          'account', req.id,
          jsonb_build_object('amount', req.amount, 'balance', w.balance, 'transfer_code', req.transfer_code)
        );
      else
        perform public.delivery_emit_notification(
          req.user_id, 'promo', 'driver_topup_rejected',
          'Yêu cầu nạp ký quỹ chưa được duyệt',
          'Mã ' || req.transfer_code || ' bị từ chối: ' || left(v_note, 200),
          'account', req.id,
          jsonb_build_object('amount', req.amount, 'reason', v_note)
        );
      end if;
    else
      if v_decision = 'approve' then
        update public.delivery_driver_wallets
          set locked_balance = greatest(0, locked_balance - req.amount),
              total_withdrawn = total_withdrawn + req.amount,
              version = version + 1,
              updated_at = now()
          where user_id = req.user_id
          returning * into w;
        insert into public.delivery_driver_wallet_ledger(
          user_id, delta, balance_after, kind, request_id, note, metadata
        ) values (
          req.user_id, 0, w.balance, 'withdraw_completed', req.id,
          'Đã chuyển khoản rút thu nhập về ' || req.bank_name || ' (' || req.bank_account_no || ') · ' || v_note,
          jsonb_build_object('amount', req.amount, 'bank_name', req.bank_name, 'bank_account_no', req.bank_account_no)
        );
        perform public.delivery_emit_notification(
          req.user_id, 'promo', 'driver_withdraw_approved',
          'Đã chuyển khoản rút tiền ' || req.amount || ' đ',
          'Khoản rút ' || req.amount || ' đ về ' || req.bank_name || ' (' || req.bank_account_no || ') đã hoàn tất.',
          'account', req.id,
          jsonb_build_object('amount', req.amount, 'bank_name', req.bank_name)
        );
      else
        update public.delivery_driver_wallets
          set locked_balance = greatest(0, locked_balance - req.amount),
              balance = balance + req.amount,
              version = version + 1,
              updated_at = now()
          where user_id = req.user_id
          returning * into w;
        insert into public.delivery_driver_wallet_ledger(
          user_id, delta, balance_after, kind, request_id, note, metadata
        ) values (
          req.user_id, req.amount, w.balance, 'withdraw_unlock_reject', req.id,
          'Hoàn lại số dư do từ chối yêu cầu rút tiền · ' || v_note,
          jsonb_build_object('amount', req.amount, 'reason', v_note)
        );
        perform public.delivery_emit_notification(
          req.user_id, 'promo', 'driver_withdraw_rejected',
          'Hoàn lại số dư yêu cầu rút tiền',
          'Yêu cầu rút ' || req.amount || ' đ bị từ chối (' || left(v_note, 180) || '). Số tiền đã mở khóa về ví.',
          'account', req.id,
          jsonb_build_object('amount', req.amount, 'balance', w.balance)
        );
      end if;
    end if;

    update public.delivery_driver_wallet_requests
      set state = case when v_decision = 'approve' then 'approved' else 'rejected' end,
          admin_note = v_note,
          reviewed_by = uid,
          reviewed_at = now(),
          version = version + 1,
          updated_at = now()
      where id = req.id
      returning * into req;

    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'driver_wallet_' || req.kind || '_' || v_decision, req.id, to_jsonb(req));

    return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));
  end if;

  -- Driver-facing actions require active driver membership (or operator inspecting)
  if not op and not public.delivery_cloud_has_membership(uid, 'driver') then
    raise sqlstate 'PT403' using message = 'Cần tư cách Đối tác Tài xế đã được duyệt để sử dụng Ví Tài xế.';
  end if;

  v_target_user := case
    when op and d ? 'driver_id' and jsonb_typeof(d->'driver_id') = 'string' and btrim(d->>'driver_id') <> ''
    then (d->>'driver_id')::uuid
    else uid
  end;

  insert into public.delivery_driver_wallets(user_id)
    values (v_target_user)
    on conflict (user_id) do nothing;

  if p_action = 'save_bank' then
    if d - array['bank_bin', 'bank_name', 'bank_account_no', 'bank_account_name'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Thông tin tài khoản ngân hàng không hợp lệ.';
    end if;
    v_bin := btrim(coalesce(d->>'bank_bin', ''));
    v_bank := btrim(coalesce(d->>'bank_name', ''));
    v_acc_no := regexp_replace(upper(btrim(coalesce(d->>'bank_account_no', ''))), '\s+', '', 'g');
    v_acc_name := upper(btrim(coalesce(d->>'bank_account_name', '')));
    if v_bin !~ '^[0-9]{6}$' or length(v_bank) not between 2 and 120
       or v_acc_no !~ '^[0-9A-Z]{6,24}$' or length(v_acc_name) not between 2 and 120 then
      raise sqlstate 'PT400' using message = 'Vui lòng nhập ngân hàng, số tài khoản (6–24 ký tự) và tên chủ tài khoản hợp lệ.';
    end if;
    update public.delivery_driver_wallets
      set bank_bin = v_bin,
          bank_name = v_bank,
          bank_account_no = v_acc_no,
          bank_account_name = v_acc_name,
          version = version + 1,
          updated_at = now()
      where user_id = uid;
    p_action := 'summary';

  elsif p_action = 'request_topup' then
    if d - array['amount', 'driver_note', 'request_key'] <> '{}'::jsonb
       or jsonb_typeof(d->'amount') is distinct from 'number'
       or (d->>'amount')::numeric <> trunc((d->>'amount')::numeric)
       or jsonb_typeof(d->'request_key') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Yêu cầu nạp ký quỹ không hợp lệ.';
    end if;
    v_amount := (d->>'amount')::integer;
    v_req_key := (d->>'request_key')::uuid;
    v_note := left(btrim(coalesce(d->>'driver_note', '')), 300);
    if v_amount not between 50000 and 50000000 then
      raise sqlstate 'PT400' using message = 'Số tiền nạp ký quỹ cần từ 50.000 đ đến 50.000.000 đ.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver-wallet:' || uid::text, 0));
    select * into req from public.delivery_driver_wallet_requests
      where user_id = uid and request_key = v_req_key;
    if found then
      select * into w from public.delivery_driver_wallets where user_id = uid;
      return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));
    end if;

    if (select count(*) from public.delivery_driver_wallet_requests where user_id = uid and kind = 'topup' and state = 'pending') >= 5 then
      raise sqlstate 'PT409' using message = 'Bạn đang có 5 yêu cầu nạp chờ duyệt. Vui lòng đợi đối soát hoặc hủy yêu cầu cũ.';
    end if;

    v_req_id := gen_random_uuid();
    insert into public.delivery_driver_wallet_requests(
      id, user_id, kind, amount, state, transfer_code, driver_note, request_key
    ) values (
      v_req_id,
      uid,
      'topup',
      v_amount,
      'pending',
      'GHST NAP ' || upper(left(replace(v_req_id::text, '-', ''), 8)),
      v_note,
      v_req_key
    ) returning * into req;

    select * into w from public.delivery_driver_wallets where user_id = uid;
    return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));

  elsif p_action = 'request_withdraw' then
    if d - array['amount', 'bank_bin', 'bank_name', 'bank_account_no', 'bank_account_name', 'driver_note', 'request_key'] <> '{}'::jsonb
       or jsonb_typeof(d->'amount') is distinct from 'number'
       or (d->>'amount')::numeric <> trunc((d->>'amount')::numeric)
       or jsonb_typeof(d->'request_key') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Yêu cầu rút thu nhập không hợp lệ.';
    end if;
    v_amount := (d->>'amount')::integer;
    v_req_key := (d->>'request_key')::uuid;
    v_note := left(btrim(coalesce(d->>'driver_note', '')), 300);
    if v_amount not between 50000 and 50000000 then
      raise sqlstate 'PT400' using message = 'Số tiền rút mỗi lần cần từ 50.000 đ đến 50.000.000 đ.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver-wallet:' || uid::text, 0));
    select * into req from public.delivery_driver_wallet_requests
      where user_id = uid and request_key = v_req_key;
    if found then
      select * into w from public.delivery_driver_wallets where user_id = uid;
      return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));
    end if;

    select * into w from public.delivery_driver_wallets where user_id = uid for update;
    v_bin := coalesce(nullif(btrim(coalesce(d->>'bank_bin', '')), ''), w.bank_bin);
    v_bank := coalesce(nullif(btrim(coalesce(d->>'bank_name', '')), ''), w.bank_name);
    v_acc_no := coalesce(nullif(regexp_replace(upper(btrim(coalesce(d->>'bank_account_no', ''))), '\s+', '', 'g'), ''), w.bank_account_no);
    v_acc_name := coalesce(nullif(upper(btrim(coalesce(d->>'bank_account_name', ''))), ''), w.bank_account_name);

    if v_bin !~ '^[0-9]{6}$' or length(v_bank) not between 2 and 120
       or v_acc_no !~ '^[0-9A-Z]{6,24}$' or length(v_acc_name) not between 2 and 120 then
      raise sqlstate 'PT400' using message = 'Vui lòng cập nhật đầy đủ ngân hàng thụ hưởng trước khi rút tiền.';
    end if;

    if w.balance < v_amount then
      raise sqlstate 'PT409' using message = 'Số dư khả dụng không đủ để rút số tiền này.';
    end if;

    v_req_id := gen_random_uuid();
    update public.delivery_driver_wallets
      set balance = balance - v_amount,
          locked_balance = locked_balance + v_amount,
          bank_bin = v_bin,
          bank_name = v_bank,
          bank_account_no = v_acc_no,
          bank_account_name = v_acc_name,
          version = version + 1,
          updated_at = now()
      where user_id = uid
      returning * into w;

    insert into public.delivery_driver_wallet_requests(
      id, user_id, kind, amount, state, transfer_code,
      bank_bin, bank_name, bank_account_no, bank_account_name, driver_note, request_key
    ) values (
      v_req_id,
      uid,
      'withdraw',
      v_amount,
      'pending',
      'GHST RUT ' || upper(left(replace(v_req_id::text, '-', ''), 8)),
      v_bin,
      v_bank,
      v_acc_no,
      v_acc_name,
      v_note,
      v_req_key
    ) returning * into req;

    insert into public.delivery_driver_wallet_ledger(
      user_id, delta, balance_after, kind, request_id, note, metadata
    ) values (
      uid,
      -v_amount,
      w.balance,
      'withdraw_lock',
      req.id,
      'Tạm khóa chờ duyệt rút tiền về ' || v_bank || ' (' || v_acc_no || ')',
      jsonb_build_object('amount', v_amount, 'bank_name', v_bank, 'bank_account_no', v_acc_no)
    );

    return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));

  elsif p_action = 'cancel_request' then
    if d - array['request_id'] <> '{}'::jsonb or jsonb_typeof(d->'request_id') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Mã yêu cầu hủy không hợp lệ.';
    end if;
    v_req_id := (d->>'request_id')::uuid;
    select * into req from public.delivery_driver_wallet_requests
      where id = v_req_id and user_id = uid for update;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy yêu cầu nạp/rút.';
    end if;
    if req.state <> 'pending' then
      raise sqlstate 'PT409' using message = 'Chỉ có thể hủy yêu cầu đang ở trạng thái chờ duyệt.';
    end if;

    select * into w from public.delivery_driver_wallets where user_id = uid for update;
    if req.kind = 'withdraw' then
      update public.delivery_driver_wallets
        set locked_balance = greatest(0, locked_balance - req.amount),
            balance = balance + req.amount,
            version = version + 1,
            updated_at = now()
        where user_id = uid
        returning * into w;
      insert into public.delivery_driver_wallet_ledger(
        user_id, delta, balance_after, kind, request_id, note, metadata
      ) values (
        uid,
        req.amount,
        w.balance,
        'withdraw_unlock_cancel',
        req.id,
        'Hoàn lại số dư do hủy yêu cầu rút ' || req.transfer_code,
        jsonb_build_object('amount', req.amount, 'transfer_code', req.transfer_code)
      );
    end if;

    update public.delivery_driver_wallet_requests
      set state = 'cancelled',
          version = version + 1,
          updated_at = now()
      where id = req.id
      returning * into req;

    return jsonb_build_object('request', to_jsonb(req), 'wallet', to_jsonb(w));
  end if;

  if p_action = 'summary' then
    select * into w from public.delivery_driver_wallets where user_id = v_target_user;
    select coalesce(sum(cash_collected_cod), 0)::bigint into v_cod_holding
      from public.delivery_cloud_orders
      where driver_id = v_target_user
        and cash_collected_cod > 0
        and status in ('inTransit', 'delivered');
    select count(*)::integer into v_trips_settled
      from public.delivery_driver_wallet_ledger
      where user_id = v_target_user and kind = 'trip_earning_80';

    return jsonb_build_object(
      'wallet', to_jsonb(w) || jsonb_build_object(
        'withdrawable_balance', greatest(0, w.balance),
        'escrow_shortfall', greatest(0, w.escrow_target - w.balance),
        'cod_holding', v_cod_holding,
        'trips_settled_count', v_trips_settled,
        'driver_share_rate', 80,
        'platform_commission_rate', 20
      ),
      'ledger', coalesce((
        select jsonb_agg(to_jsonb(l) order by l.created_at desc, l.id desc)
        from (
          select * from public.delivery_driver_wallet_ledger
          where user_id = v_target_user
          order by created_at desc, id desc
          limit 40
        ) l
      ), '[]'::jsonb),
      'requests', coalesce((
        select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc)
        from (
          select * from public.delivery_driver_wallet_requests
          where user_id = v_target_user
          order by created_at desc, id desc
          limit 30
        ) r
      ), '[]'::jsonb)
    );
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác ví tài xế không hỗ trợ.';
end; $$;

revoke all on function public.delivery_driver_wallet(text, jsonb) from public, anon;
grant execute on function public.delivery_driver_wallet(text, jsonb) to authenticated;


-- ============================================================================
-- PART 2: VIRTUAL SHOWCASE STORES, RESTAURANTS & BEVERAGE CATALOG
-- ============================================================================

alter table public.delivery_market_shops
  add column if not exists is_showcase boolean not null default false;
alter table public.delivery_market_shops
  add column if not exists showcase_slug text unique;
alter table public.delivery_market_shops
  add column if not exists category_group text not null default '' check (length(category_group) <= 60);
alter table public.delivery_market_shops
  add column if not exists showcase_auto_dispatch boolean not null default true;

alter table public.delivery_market_shops
  drop constraint if exists delivery_market_shops_owner_id_key;

create unique index if not exists delivery_market_shops_primary_owner_idx
  on public.delivery_market_shops(owner_id)
  where not is_showcase;

-- Auto-dispatch helper for virtual showcase food/beverage/convenience orders
create or replace function public.delivery_showcase_auto_dispatch_order(
  p_order_id uuid,
  p_actor uuid
) returns void
language plpgsql security definer set search_path='' as $$
declare
  so public.delivery_market_shop_orders;
  sh public.delivery_market_shops;
  purchase public.delivery_market_purchases;
  shipment public.delivery_cloud_orders;
  expected_cod bigint := 0;
begin
  select * into so from public.delivery_market_shop_orders where id = p_order_id for update;
  if not found or so.state <> 'pending' or so.delivery_id is not null then
    return;
  end if;
  select * into sh from public.delivery_market_shops where id = so.shop_id;
  if not found or not sh.is_showcase or not sh.showcase_auto_dispatch then
    return;
  end if;
  select * into purchase from public.delivery_market_purchases where id = so.purchase_id;
  if purchase.payment_method = 'prepaid' and purchase.payment_status <> 'PAID' then
    return;
  end if;

  expected_cod := case
    when purchase.payment_method = 'prepaid' then 0
    else coalesce((so.snapshot->>'payable_subtotal')::bigint, (so.snapshot->>'subtotal')::bigint)
  end;

  insert into public.delivery_cloud_orders(
    owner_id, merchant_id, request_key, request_payload, details, distance_meters,
    shipping_fee, cod_amount, pricing_version, merchant_ready
  ) values (
    so.owner_id,
    so.merchant_id,
    gen_random_uuid(),
    jsonb_build_object('shop_order', so.id, 'showcase_auto_dispatch', true),
    so.snapshot->'details',
    (so.snapshot->>'distance_meters')::integer,
    (so.snapshot->>'shipping_fee')::integer,
    expected_cod::integer,
    (so.snapshot->>'pricing_version')::integer,
    true
  ) returning * into shipment;

  if coalesce((so.snapshot->'details'->>'require_otp')::boolean, false) then
    insert into public.delivery_cloud_order_secrets(order_id, otp_code, otp_hash)
      select shipment.id, otp_code, encode(sha256(convert_to(otp_code, 'UTF8')), 'hex')
      from (
        select ((
          get_byte(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 0) * 65536 +
          get_byte(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 1) * 256 +
          get_byte(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 2)
        ) % 900000 + 100000)::text as otp_code
      ) g;
  end if;

  insert into public.delivery_live_rooms(id) values (shipment.tracking_code) on conflict do nothing;
  insert into public.delivery_live_members(room_id, user_id, role)
    values (shipment.tracking_code, so.owner_id, 'customer')
    on conflict (room_id, user_id) do nothing;
  insert into public.delivery_live_members(room_id, user_id, role)
    values (shipment.tracking_code, so.merchant_id, 'merchant')
    on conflict (room_id, user_id) do nothing;

  insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
    values (shipment.id, coalesce(p_actor, so.merchant_id), 'create', shipment.status, 1, 'Cửa hàng tự động xác nhận & gọi tài xế');
  insert into public.delivery_live_events(room_id, kind, payload)
    values (shipment.tracking_code, 'status', jsonb_build_object('status', shipment.status, 'version', 1));

  update public.delivery_market_shop_orders
    set state = 'ready',
        delivery_id = shipment.id,
        version = version + 1,
        updated_at = now()
    where id = so.id;

  update public.delivery_market_jobs
    set state = 'done', completed_at = now()
    where order_id = so.id and state = 'pending';

  insert into public.delivery_market_events(order_id, actor_id, actor_source, action, reason)
    values
      (so.id, coalesce(p_actor, so.merchant_id), 'system', 'accept', 'Quán tự động tiếp nhận đơn'),
      (so.id, coalesce(p_actor, so.merchant_id), 'system', 'ready', 'Món đã sẵn sàng giao cho tài xế');
  insert into public.delivery_market_notifications(user_id, order_id, kind)
    values (so.owner_id, so.id, 'ready');
end; $$;

revoke all on function public.delivery_showcase_auto_dispatch_order(uuid, uuid) from public, anon, authenticated;

-- Update shop ownership/delegation helper to support showcase stores & operator management
create or replace function public.delivery_market_can_access_shop(
  p_shop uuid,
  p_user uuid,
  p_min_role text default 'staff'
) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.delivery_market_shops s
    join public.delivery_cloud_accounts oa on oa.user_id = s.owner_id
    where s.id = p_shop and not oa.blocked
      and (s.is_showcase or public.delivery_cloud_has_membership(s.owner_id, 'merchant'))
      and (
        (s.is_showcase and p_user = auth.uid() and public.delivery_is_operator())
        or (s.owner_id = p_user and p_min_role in ('owner', 'manager', 'staff'))
        or (
          p_min_role in ('manager', 'staff') and exists(
            select 1 from public.delivery_market_shop_staff st
            join public.delivery_cloud_accounts ua on ua.user_id = st.user_id
            where st.shop_id = s.id and st.user_id = p_user and st.active and not ua.blocked
              and (p_min_role = 'staff' or st.role = 'manager')
          )
        )
      )
  );
$$;
revoke all on function public.delivery_market_can_access_shop(uuid, uuid, text) from public, anon, authenticated;

-- Update configured cart projection for showcase shops
create or replace function public.delivery_market_configured_cart() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; row record; sel jsonb; available boolean; cv integer; stock_ok boolean;
begin
  select version into cv from public.delivery_market_carts where user_id=auth.uid();
  for row in select p.*,c.line_id,c.selected_options,c.variant_id,c.quantity,s.name as shop_name,s.status as shop_status,s.paused,
    s.opening_schedule,m.blocked as merchant_blocked,(s.is_showcase or public.delivery_cloud_has_membership(m.user_id,'merchant')) as merchant_active
    from public.delivery_market_cart_items c join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
    where c.user_id=auth.uid() order by p.shop_id,c.line_id loop
    begin
      sel:=public.delivery_market_selection_v2(row.id,row.selected_options,row.variant_id,row.quantity,auth.uid());
      if row.variant_id is not null then
        stock_ok:=exists(select 1 from public.delivery_market_variants v where v.id=row.variant_id and v.product_id=row.id and v.published and
          v.stock>=(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and variant_id=row.variant_id));
      else
        stock_ok:=row.stock>=(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=row.id and variant_id is null);
      end if;
      available:=row.published and row.shop_status='active' and not row.paused and not row.merchant_blocked and row.merchant_active and
        public.delivery_market_is_open(row.opening_schedule) and public.delivery_market_is_open(row.sale_schedule) and stock_ok;
    exception when sqlstate 'PT409' or sqlstate 'PT404' then
      sel:=jsonb_build_object('unit_price',null,'options','[]'::jsonb,'variant_title',null,'flash_sale_id',null);
      available:=false;
    end;
    result:=result||jsonb_build_array(
      (to_jsonb(row)-array['merchant_blocked','merchant_active','opening_schedule'])||
      jsonb_build_object('unit_price',sel->'unit_price','options',sel->'options','available',available)||
      case when row.variant_id is not null then jsonb_build_object('variant_id',row.variant_id,'variant_title',sel->'variant_title','sku',coalesce(sel->>'effective_sku',row.sku)) else '{}'::jsonb end||
      case when sel->'flash_sale_id' is not null and jsonb_typeof(sel->'flash_sale_id')<>'null' then jsonb_build_object('flash_sale_id',sel->'flash_sale_id') else '{}'::jsonb end
    );
  end loop;
  return jsonb_build_object('version',coalesce(cv,1),'items',result);
end$$;
revoke all on function public.delivery_market_configured_cart() from public,anon,authenticated;

-- Update quote snapshot v2 so showcase shops can be ordered by any account (including seeding operator)
create or replace function public.delivery_market_snapshot_v2(p_address uuid,p_options jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_addresses; s record; i record; v public.delivery_market_variants;
  voucher public.delivery_market_vouchers; items jsonb; item_obj jsonb; shops jsonb:='[]'; final_shops jsonb:='[]';
  subtotal bigint; goods_total bigint:=0; freight_total bigint:=0; total bigint:=0;
  weight numeric; vol_weight numeric; eff_weight numeric; details jsonb; q jsonb; cart_version integer; sel jsonb;
  has_opts boolean:=p_options is not null and p_options<>'{}'::jsonb;
  v_service text:=coalesce(p_options->>'service_type','standard');
  v_pay text:=coalesce(p_options->>'payment_method','cod');
  v_note text:=btrim(coalesce(p_options->>'buyer_note',''));
  v_sched text:=nullif(btrim(coalesce(p_options->>'scheduled_at','')),'');
  v_ev boolean:=coalesce((p_options->>'prefer_ev')::boolean,false);
  v_pod boolean:=coalesce((p_options->>'require_pod')::boolean,false);
  v_otp boolean:=coalesce((p_options->>'require_otp')::boolean,false);
  v_code text:=upper(btrim(coalesce(p_options->>'voucher_code','')));
  v_use_coins boolean:=coalesce((p_options->>'use_coins')::boolean,false);
  voucher_disc bigint:=0; coin_disc bigint:=0; wallet_bal bigint:=0; used_count integer:=0;
  rem_platform bigint:=0; shop_row jsonb; idx integer:=0; shop_cnt integer:=0;
  sh_sub bigint; sh_vdisc bigint; sh_pdisc bigint; sh_pay bigint;
begin
  if jsonb_typeof(coalesce(p_options,'{}'::jsonb))<>'object' or
     (coalesce(p_options,'{}'::jsonb)-array['buyer_note','service_type','payment_method','scheduled_at','prefer_ev','require_pod','require_otp','voucher_code','use_coins'])<>'{}'::jsonb then
    raise sqlstate 'PT400' using message='Tùy chọn đặt hàng không hợp lệ.';
  end if;
  if v_service not in ('standard','express','saving','same_day_2h','truck') or v_pay not in ('cod','prepaid') or length(v_note)>500 then
    raise sqlstate 'PT400' using message='Phương thức vận chuyển, thanh toán hoặc ghi chú không hợp lệ.';
  end if;
  if v_sched is not null and (v_sched::timestamptz < now()+interval '10 minutes' or v_sched::timestamptz > now()+interval '7 days') then
    raise sqlstate 'PT400' using message='Lịch hẹn giao hàng cần từ 10 phút tới 7 ngày.';
  end if;

  select * into a from public.delivery_cloud_addresses where id=p_address and user_id=auth.uid();
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ nhận hàng.'; end if;
  select version into cart_version from public.delivery_market_carts where user_id=auth.uid();
  if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid()) then
    raise sqlstate 'PT400' using message='Giỏ hàng đang trống.'; end if;

  for s in select distinct sh.* from public.delivery_market_cart_items c
    join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops sh on sh.id=p.shop_id where c.user_id=auth.uid() order by sh.id loop
    if s.status<>'active' or s.paused or (v_sched is null and not public.delivery_market_is_open(s.opening_schedule)) or
      (v_sched is not null and not public.delivery_market_is_open(s.opening_schedule,v_sched::timestamptz)) or
      not exists(select 1 from public.delivery_cloud_accounts where user_id=s.owner_id and
        (s.is_showcase or public.delivery_cloud_has_membership(user_id,'merchant')) and not blocked) then
      raise sqlstate 'PT409' using message='Cửa hàng tạm ngừng nhận đơn.'; end if;
    if not s.is_showcase and s.owner_id=auth.uid() then
      raise sqlstate 'PT400' using message='Không thể mua hàng từ cửa hàng của chính mình.';
    end if;

    items:='[]'; subtotal:=0; weight:=0; vol_weight:=0;
    for i in select p.*,c.quantity,c.line_id,c.selected_options,c.variant_id from public.delivery_market_cart_items c
      join public.delivery_market_products p on p.id=c.product_id
      where c.user_id=auth.uid() and p.shop_id=s.id order by p.id,c.line_id loop
      if not i.published or (v_sched is null and not public.delivery_market_is_open(i.sale_schedule)) or
         (v_sched is not null and not public.delivery_market_is_open(i.sale_schedule,v_sched::timestamptz)) then
        raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc ngoài khung giờ mở bán.';
      end if;
      if i.variant_id is not null then
        select * into v from public.delivery_market_variants where id=i.variant_id and product_id=i.id and published;
        if not found or v.stock<(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and variant_id=i.variant_id) then
          raise sqlstate 'PT409' using message='Biến thể ngừng bán hoặc không đủ tồn kho.';
        end if;
      else
        if i.stock<(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=i.id and variant_id is null) then
          raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc không đủ tồn kho.';
        end if;
      end if;
      sel:=public.delivery_market_selection_v2(i.id,i.selected_options,i.variant_id,i.quantity,auth.uid());
      subtotal:=subtotal+(sel->>'unit_price')::bigint*i.quantity;
      weight:=weight+(sel->>'effective_weight_kg')::numeric*i.quantity;
      if (sel->>'length_cm')::numeric>0 and (sel->>'width_cm')::numeric>0 and (sel->>'height_cm')::numeric>0 then
        vol_weight:=vol_weight+round(((sel->>'length_cm')::numeric*(sel->>'width_cm')::numeric*(sel->>'height_cm')::numeric)/5000.0,2)*i.quantity;
      end if;
      item_obj:=jsonb_build_object(
        'product_id',i.id,'line_id',i.line_id,'name',i.name,'sku',coalesce(sel->>'effective_sku',i.sku),
        'quantity',i.quantity,'unit_price',sel->'unit_price','selected_options',sel->'selected_options',
        'options',sel->'options','preparation_minutes',i.preparation_minutes,
        'version',(sel->>'effective_terms_version')::integer,'image_url',i.image_url
      ) || case when i.variant_id is not null then jsonb_build_object('variant_id',i.variant_id,'variant_title',sel->'variant_title') else '{}'::jsonb end
        || case when sel->'flash_sale_id' is not null and jsonb_typeof(sel->'flash_sale_id')<>'null' then jsonb_build_object('flash_sale_id',sel->'flash_sale_id') else '{}'::jsonb end;
      items:=items||jsonb_build_array(item_obj);
    end loop;

    eff_weight:=greatest(weight,vol_weight);
    if subtotal>20000000 or eff_weight>(case when v_service='truck' then 500 else 30 end) then
      raise sqlstate 'PT400' using message='Đơn vượt giới hạn giá trị hoặc khối lượng của dịch vụ vận chuyển.';
    end if;
    details:=jsonb_build_object(
      'pickup_address',s.address,'pickup_lat',s.latitude,'pickup_lng',s.longitude,
      'dropoff_address',a.full_address,'dropoff_lat',a.latitude,'dropoff_lng',a.longitude,
      'recipient_name',a.recipient_name,'recipient_phone',a.recipient_phone,
      'package_description','Hàng mua tại '||s.name,'weight_kg',eff_weight,'service_type',v_service,
      'payment_method',case when v_pay='prepaid' then 'sender_cash' else 'recipient_cash' end,
      'cod_amount',case when v_pay='prepaid' then 0 else subtotal end,'merchant_id',s.owner_id
    ) || case when v_note<>'' then jsonb_build_object('buyer_note',v_note) else '{}'::jsonb end
      || case when v_sched is not null then jsonb_build_object('scheduled_at',v_sched) else '{}'::jsonb end
      || case when v_ev then jsonb_build_object('prefer_ev',true) else '{}'::jsonb end
      || case when v_pod then jsonb_build_object('require_pod',true) else '{}'::jsonb end
      || case when v_otp then jsonb_build_object('require_otp',true) else '{}'::jsonb end;
    q:=public.delivery_cloud_quote(details);
    if s.service_radius_km>0 and (q->>'distance_meters')::numeric > s.service_radius_km*1000 then
      raise sqlstate 'PT409' using message='Địa chỉ nhận hàng nằm ngoài bán kính phục vụ của '||s.name||'.';
    end if;
    shops:=shops||jsonb_build_array(jsonb_build_object(
      'shop_id',s.id,'shop_name',s.name,'shop_version',s.version,
      'merchant_id',s.owner_id,'items',items,'subtotal',subtotal,'shipping_fee',q->'shipping_fee',
      'pricing_version',q->'pricing_version','distance_meters',q->'distance_meters','details',details
    ));
    goods_total:=goods_total+subtotal;
    freight_total:=freight_total+(q->>'shipping_fee')::bigint;
  end loop;

  if not has_opts then
    total:=goods_total+freight_total;
    if total not between 1 and 100000000 then raise sqlstate 'PT400' using message='Tổng giỏ hàng vượt giới hạn.'; end if;
    return jsonb_build_object('address_id',a.id,'address_version',a.version,'cart_version',cart_version,'shops',shops,'total',total);
  end if;

  if v_code<>'' then
    select * into voucher from public.delivery_market_vouchers
      where code=v_code and active and starts_at<=now() and ends_at>now()
        and (owner_user_id is null or owner_user_id=auth.uid());
    if not found then raise sqlstate 'PT409' using message='Mã giảm giá không tồn tại hoặc đã hết hạn.'; end if;
    select count(*) into used_count from public.delivery_market_voucher_usages
      where voucher_id=voucher.id and user_id=auth.uid() and state='allocated';
    if used_count>=voucher.per_user_limit then raise sqlstate 'PT409' using message='Bạn đã dùng hết lượt mã giảm giá này.'; end if;
    if voucher.shop_id is not null then
      select (g->>'subtotal')::bigint into sh_sub from jsonb_array_elements(shops) g where (g->>'shop_id')::uuid=voucher.shop_id;
      if sh_sub is null or sh_sub<voucher.min_subtotal then
        raise sqlstate 'PT409' using message='Đơn tại cửa hàng chưa đạt giá trị tối thiểu của mã giảm giá.';
      end if;
      voucher_disc:=least(sh_sub,voucher.max_discount,case when voucher.discount_kind='fixed' then voucher.discount_value::bigint else round(sh_sub*voucher.discount_value/100.0)::bigint end);
    else
      if goods_total<voucher.min_subtotal then raise sqlstate 'PT409' using message='Giỏ hàng chưa đạt giá trị tối thiểu của mã giảm giá.'; end if;
      voucher_disc:=least(goods_total,voucher.max_discount,case when voucher.discount_kind='fixed' then voucher.discount_value::bigint else round(goods_total*voucher.discount_value/100.0)::bigint end);
    end if;
    if voucher_disc<=0 or voucher.budget_used+voucher_disc>voucher.budget_total then
      raise sqlstate 'PT409' using message='Ngân sách mã giảm giá đã hết.';
    end if;
  end if;

  if v_use_coins then
    select coalesce(balance,0) into wallet_bal from public.delivery_market_coin_wallets where user_id=auth.uid();
    coin_disc:=least(
      wallet_bal,
      floor(greatest(0, goods_total - voucher_disc + freight_total) * 0.20)::bigint,
      greatest(0, goods_total - voucher_disc)
    );
  end if;

  rem_platform:=(case when voucher.id is not null and voucher.shop_id is null then voucher_disc else 0 end)+coin_disc;
  shop_cnt:=jsonb_array_length(shops);
  for shop_row in select * from jsonb_array_elements(shops) loop
    idx:=idx+1;
    sh_sub:=(shop_row->>'subtotal')::bigint;
    sh_vdisc:=case when voucher.id is not null and voucher.shop_id=(shop_row->>'shop_id')::uuid then voucher_disc else 0 end;
    if rem_platform>0 then
      if idx=shop_cnt then sh_pdisc:=least(sh_sub-sh_vdisc,rem_platform);
      else sh_pdisc:=least(sh_sub-sh_vdisc,floor(((case when voucher.id is not null and voucher.shop_id is null then voucher_disc else 0 end)+coin_disc)*sh_sub::numeric/greatest(1,goods_total))::bigint);
      end if;
      rem_platform:=greatest(0,rem_platform-sh_pdisc);
    else sh_pdisc:=0;
    end if;
    sh_pay:=greatest(0,sh_sub-sh_vdisc-sh_pdisc);
    details:=jsonb_set(shop_row->'details','{cod_amount}',to_jsonb(case when v_pay='prepaid' then 0::bigint else sh_pay end));
    final_shops:=final_shops||jsonb_build_array(
      jsonb_set(shop_row,'{details}',details)||jsonb_build_object(
        'shop_discount',sh_vdisc,'platform_discount',sh_pdisc,'payable_subtotal',sh_pay,
        'buyer_note',v_note,'scheduled_at',v_sched,'payment_method',v_pay
      )
    );
  end loop;

  total:=greatest(1,goods_total-voucher_disc-coin_disc+freight_total);
  if total not between 1 and 100000000 then raise sqlstate 'PT400' using message='Tổng giỏ hàng vượt giới hạn.'; end if;
  return jsonb_build_object(
    'address_id',a.id,'address_version',a.version,'cart_version',cart_version,
    'shops',final_shops,'goods_subtotal',goods_total,'shipping_total',freight_total,
    'voucher_id',voucher.id,'voucher_code',nullif(v_code,''),'voucher_discount',voucher_disc,
    'coin_discount',coin_disc,'discount_total',voucher_disc+coin_disc,
    'payment_method',v_pay,'checkout_options',p_options,'total',total
  );
end$$;
revoke all on function public.delivery_market_snapshot_v2(uuid,jsonb) from public,anon,authenticated;

-- Update prepaid capture so prepaid showcase orders also auto-dispatch to drivers upon payment
create or replace function public.delivery_market_record_prepaid_capture(p_purchase uuid,p_reference text) returns text
language plpgsql security definer set search_path='' as $$
declare p public.delivery_market_purchases; so public.delivery_market_shop_orders; f public.delivery_market_finance;
  jid uuid; goods bigint; shop_disc bigint; plat_disc bigint; freight bigint; cash_due bigint; merch_net bigint;
begin
  select * into p from public.delivery_market_purchases where id=p_purchase for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy giao dịch mua hàng.'; end if;
  if exists(select 1 from public.delivery_market_shop_orders where purchase_id=p.id and state='cancelled') then
    update public.delivery_market_purchases set payment_status='REVIEW' where id=p.id;
    return 'REVIEW';
  end if;
  update public.delivery_market_purchases set payment_status='PAID' where id=p.id;
  for so in select * from public.delivery_market_shop_orders where purchase_id=p.id order by id for update loop
    if not exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='collection' and state='completed') then
      goods:=(so.snapshot->>'subtotal')::bigint;
      shop_disc:=coalesce((so.snapshot->>'shop_discount')::bigint,0);
      plat_disc:=coalesce((so.snapshot->>'platform_discount')::bigint,0);
      freight:=(so.snapshot->>'shipping_fee')::bigint;
      merch_net:=greatest(0,goods-shop_disc);
      cash_due:=greatest(1,goods-shop_disc-plat_disc+freight);
      insert into public.delivery_market_finance(order_id,kind,amount,proposer,reason,evidence,completion_evidence,state,source,request_key,completed_at)
        values(so.id,'collection',cash_due::integer,p.owner_id,'Thanh toán trực tuyến payOS','payOS:'||left(p_reference,180),'payOS:'||left(p_reference,180),'completed','provider',gen_random_uuid(),now())
        returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;
      insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'cash_clearing',cash_due);
      if plat_disc>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'promo_expense',plat_disc); end if;
      if merch_net>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'merchant_payable',-merch_net); end if;
      if freight>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'shipping_revenue',-freight); end if;
      update public.delivery_market_shop_orders set accept_by=greatest(accept_by,now()+interval '15 minutes') where id=so.id;
      update public.delivery_market_jobs set run_at=greatest(run_at,now()+interval '15 minutes') where order_id=so.id and state='pending';
    end if;
    perform public.delivery_showcase_auto_dispatch_order(so.id, p.owner_id);
  end loop;
  return 'PAID';
end$$;
revoke all on function public.delivery_market_record_prepaid_capture(uuid,text) from public,anon,authenticated;

-- Update delivery_marketplace for partial primary-shop index, showcase cart/checkout & auto-dispatch
create or replace function public.delivery_marketplace(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor public.delivery_cloud_accounts; sh public.delivery_market_shops; prod public.delivery_market_products;
  previous public.delivery_market_products; var_row public.delivery_market_variants; prev_var public.delivery_market_variants;
  voucher_row public.delivery_market_vouchers; flash_row public.delivery_market_flash_sales;
  purchase public.delivery_market_purchases; so public.delivery_market_shop_orders;
  quote public.delivery_market_quotes; shipment public.delivery_cloud_orders; msg public.delivery_market_messages;
  d jsonb:=p_payload; result jsonb; snapshot jsonb; group_row jsonb; item jsonb; parcel jsonb;
  cart_version integer; qty integer; product_key uuid; variant_key uuid; requested text; line_key uuid;
  selected jsonb; selection jsonb; aggregate_qty bigint; op boolean;
  staff_user uuid; att_list jsonb:='[]'; att_name text; idx integer:=0;
  coin_total bigint:=0; coin_rem bigint:=0; sh_cnt integer:=0; sh_idx integer:=0; sh_coin bigint:=0;
  v_id uuid; fs_id uuid; split_cod bigint:=0; expected_cod bigint:=0; parcel_weight numeric;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into actor from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op:=public.delivery_is_operator();
  if (actor.user_id is null or actor.blocked) and not (p_action in ('workspace','shop_moderate','voucher_save') and op) then
    raise sqlstate 'PT403' using message='Cần hồ sơ tài khoản đang hoạt động.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.'; end if;

  if p_action='catalog' then
    if length(coalesce(d->>'search',''))>160 or length(coalesce(d->>'category',''))>80 then raise sqlstate 'PT400' using message='Bộ lọc quá dài.'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select p.*,s.name as shop_name,s.is_showcase,s.category_group from public.delivery_market_products p
      join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(a.user_id,'merchant'))
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d ? 'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid)
      order by p.id limit 50
    ) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);

  elsif p_action='workspace' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not op and
       not exists(select 1 from public.delivery_market_shop_staff st where st.user_id=auth.uid() and st.active and public.delivery_market_can_access_shop(st.shop_id,auth.uid(),'staff')) then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    result:=jsonb_build_object(
      'shops',coalesce((select jsonb_agg(to_jsonb(x) order by (case when d->>'moderation'='true' then true else not x.is_showcase end) desc, x.id asc) from
        (select s.* from public.delivery_market_shops s
         where ((s.owner_id=auth.uid() and (not s.is_showcase or d->>'moderation'='true'))
                or public.delivery_market_can_access_shop(s.id,auth.uid(),'staff')
                or (d->>'moderation'='true' and op))
           and (d->>'moderation' is distinct from 'true' or not(d ? 'after') or s.id>(d->>'after')::uuid)
         order by s.id limit 50) x),'[]'),
      'products',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
        (select p.*,
           coalesce((select jsonb_agg(to_jsonb(v) order by v.sku,v.id) from public.delivery_market_variants v where v.product_id=p.id),'[]'::jsonb) as variants
         from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
         where ((s.owner_id=auth.uid() and not s.is_showcase) or (not s.is_showcase and public.delivery_market_can_access_shop(s.id,auth.uid(),'staff')))
           and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x),'[]'),
      'staff',coalesce((select jsonb_agg(jsonb_build_object('shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,'role',st.role,'active',st.active,'version',st.version) order by st.created_at,st.user_id)
        from public.delivery_market_shop_staff st join public.delivery_market_shops s on s.id=st.shop_id
        join public.delivery_cloud_accounts ua on ua.user_id=st.user_id
        where s.owner_id=auth.uid() and not s.is_showcase and st.active),'[]'),
      'vouchers',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc) from
        (select v.* from public.delivery_market_vouchers v
         where (op and d->>'moderation'='true') or (v.shop_id is not null and public.delivery_market_can_access_shop(v.shop_id,auth.uid(),'staff'))
         order by v.created_at desc,v.id desc limit 50) v),'[]'),
      'flash_sales',coalesce((select jsonb_agg(to_jsonb(fs) order by fs.starts_at desc,fs.id desc) from
        (select fs.* from public.delivery_market_flash_sales fs
         where (op and d->>'moderation'='true') or public.delivery_market_can_access_shop(fs.shop_id,auth.uid(),'staff')
         order by fs.starts_at desc,fs.id desc limit 50) fs),'[]')
    );
    snapshot:=result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);

  elsif p_action='shop_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['name','description','address','latitude','longitude','paused','version','opening_schedule','banner_url','service_radius_km']<>'{}' or
      jsonb_typeof(d->'name') is distinct from 'string' or jsonb_typeof(d->'address') is distinct from 'string' or
      jsonb_typeof(d->'latitude') is distinct from 'number' or jsonb_typeof(d->'longitude') is distinct from 'number' or
      jsonb_typeof(d->'paused') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Thông tin cửa hàng không hợp lệ.'; end if;
    if (d ? 'service_radius_km' and (jsonb_typeof(d->'service_radius_km')<>'number' or (d->>'service_radius_km')::numeric not between 0 and 200)) or
       (d ? 'banner_url' and (jsonb_typeof(d->'banner_url')<>'string' or length(d->>'banner_url')>1000 or (d->>'banner_url'<>'' and (d->>'banner_url') !~ '^https://'))) then
      raise sqlstate 'PT400' using message='Ảnh bìa hoặc bán kính phục vụ không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('shop:'||auth.uid()::text,0));
    select * into sh from public.delivery_market_shops where owner_id=auth.uid() and not is_showcase for update;
    if sh.id is not null and sh.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi. Hãy tải lại.'; end if;
    if sh.status='suspended' then raise sqlstate 'PT403' using message='Cửa hàng đang tạm khóa.'; end if;
    insert into public.delivery_market_shops(owner_id,name,description,address,latitude,longitude,paused,is_showcase)
      values(auth.uid(),btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'address'),(d->>'latitude')::float8,(d->>'longitude')::float8,(d->>'paused')::boolean,false)
      on conflict(owner_id) where not is_showcase do update set name=excluded.name,description=excluded.description,address=excluded.address,
        latitude=excluded.latitude,longitude=excluded.longitude,paused=excluded.paused,version=delivery_market_shops.version+1,
        status=case when delivery_market_shops.name=excluded.name and delivery_market_shops.address=excluded.address
          and delivery_market_shops.latitude=excluded.latitude and delivery_market_shops.longitude=excluded.longitude
          then delivery_market_shops.status else 'pending' end,updated_at=now() returning * into sh;
    update public.delivery_market_shops set
      opening_schedule=coalesce(d->'opening_schedule',opening_schedule),
      banner_url=case when d ? 'banner_url' then d->>'banner_url' else banner_url end,
      service_radius_km=case when d ? 'service_radius_km' then (d->>'service_radius_km')::numeric else service_radius_km end
      where id=sh.id returning * into sh;
    return jsonb_build_object('shop',to_jsonb(sh));

  elsif p_action='staff_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Chỉ chủ cửa hàng quản lý nhân sự.'; end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and owner_id=auth.uid() for update;
    if not found or sh.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền quản lý nhân sự cửa hàng này.'; end if;
    if d ? 'user_id' and jsonb_typeof(d->'user_id')='string' then
      staff_user:=(d->>'user_id')::uuid;
    elsif d ? 'phone' and jsonb_typeof(d->'phone')='string' then
      select user_id into staff_user from public.delivery_cloud_accounts where phone=btrim(d->>'phone') and not blocked order by updated_at desc limit 1;
    end if;
    if staff_user is null or staff_user=auth.uid() or not exists(select 1 from public.delivery_cloud_accounts where user_id=staff_user and not blocked) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản nhân viên hợp lệ.';
    end if;
    if coalesce(d->>'role','staff') not in ('manager','staff') or jsonb_typeof(coalesce(d->'active','true'::jsonb))<>'boolean' then
      raise sqlstate 'PT400' using message='Quyền nhân sự không hợp lệ.';
    end if;
    insert into public.delivery_market_shop_staff(shop_id,user_id,role,active,added_by)
      values(sh.id,staff_user,coalesce(d->>'role','staff'),coalesce((d->>'active')::boolean,true),auth.uid())
      on conflict(shop_id,user_id) do update set role=excluded.role,active=excluded.active,version=delivery_market_shop_staff.version+1,updated_at=now();
    return jsonb_build_object('staff',coalesce((select jsonb_agg(jsonb_build_object('shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,'role',st.role,'active',st.active,'version',st.version) order by st.created_at,st.user_id)
      from public.delivery_market_shop_staff st join public.delivery_cloud_accounts ua on ua.user_id=st.user_id where st.shop_id=sh.id and st.active),'[]'::jsonb));

  elsif p_action='shop_moderate' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if d->>'status' not in ('active','suspended') or not(d ?& array['id','version','status']) then raise sqlstate 'PT400' using message='Trạng thái không hợp lệ.'; end if;
    update public.delivery_market_shops set status=d->>'status',version=version+1,updated_at=now()
      where id=(d->>'id')::uuid and version=(d->>'version')::integer returning * into sh;
    if not found then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi hoặc không tồn tại.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'shop_moderate',sh.id,to_jsonb(sh));
    return jsonb_build_object('shop',to_jsonb(sh));

  elsif p_action='product_save' then
    if d-array['id','shop_id','name','description','category','sku','image_url','price','stock','weight_kg','published','version','option_groups','sale_schedule','preparation_minutes','images','length_cm','width_cm','height_cm']<>'{}' or
      jsonb_typeof(d->'price') is distinct from 'number' or jsonb_typeof(d->'stock') is distinct from 'number' or
      jsonb_typeof(d->'weight_kg') is distinct from 'number' or jsonb_typeof(d->'published') is distinct from 'boolean' or
      (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) or (d->>'price')::numeric<>trunc((d->>'price')::numeric) then
      raise sqlstate 'PT400' using message='Giá và tồn kho cần là số nguyên hợp lệ.';
    end if;
    if d?'preparation_minutes' and (jsonb_typeof(d->'preparation_minutes') is distinct from 'number' or
      (d->>'preparation_minutes')::numeric<>trunc((d->>'preparation_minutes')::numeric) or
      (d->>'preparation_minutes')::numeric not between 0 and 1440) then
      raise sqlstate 'PT400' using message='Thời gian chuẩn bị không hợp lệ.'; end if;
    if (d ? 'length_cm' and (jsonb_typeof(d->'length_cm')<>'number' or (d->>'length_cm')::numeric not between 0 and 300)) or
       (d ? 'width_cm' and (jsonb_typeof(d->'width_cm')<>'number' or (d->>'width_cm')::numeric not between 0 and 300)) or
       (d ? 'height_cm' and (jsonb_typeof(d->'height_cm')<>'number' or (d->>'height_cm')::numeric not between 0 and 300)) then
      raise sqlstate 'PT400' using message='Kích thước sản phẩm không hợp lệ.';
    end if;
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not public.delivery_market_can_access_shop((d->>'shop_id')::uuid,auth.uid(),'manager') then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and public.delivery_market_can_access_shop(id,auth.uid(),'manager') for update;
    if not found or sh.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền sửa cửa hàng này.'; end if;
    product_key:=(d->>'id')::uuid;
    if product_key is null then raise sqlstate 'PT400' using message='Thiếu mã sản phẩm.'; end if;
    select * into previous from public.delivery_market_products where delivery_market_products.id=product_key for update;
    if previous.id is not null and (previous.shop_id<>sh.id or previous.version is distinct from (d->>'version')::integer) then
      raise sqlstate 'PT409' using message='Sản phẩm đã thay đổi hoặc thuộc cửa hàng khác.';
    end if;
    if previous.id is null and d->>'version' is not null then raise sqlstate 'PT409' using message='Sản phẩm không còn tồn tại.'; end if;
    insert into public.delivery_market_products(id,shop_id,name,description,category,sku,image_url,price,stock,weight_kg,published)
      values(product_key,sh.id,btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'category'),btrim(d->>'sku'),coalesce(d->>'image_url',''),
        (d->>'price')::integer,(d->>'stock')::integer,(d->>'weight_kg')::numeric,(d->>'published')::boolean)
      on conflict on constraint delivery_market_products_pkey do update set name=excluded.name,description=excluded.description,
        category=excluded.category,sku=excluded.sku,image_url=excluded.image_url,price=excluded.price,stock=excluded.stock,
        weight_kg=excluded.weight_kg,published=excluded.published,version=delivery_market_products.version+1,updated_at=now()
      returning * into prod;
    if prod.stock<>coalesce(previous.stock,0) then
      insert into public.delivery_market_stock(product_id,actor_id,delta,reason) values(prod.id,auth.uid(),prod.stock-coalesce(previous.stock,0),'merchant_adjust');
    end if;
    update public.delivery_market_products set option_groups=coalesce(d->'option_groups',option_groups),
      sale_schedule=coalesce(d->'sale_schedule',sale_schedule),images=coalesce(d->'images',images),
      preparation_minutes=case when d?'preparation_minutes' then (d->>'preparation_minutes')::integer else preparation_minutes end,
      length_cm=case when d?'length_cm' then (d->>'length_cm')::numeric else length_cm end,
      width_cm=case when d?'width_cm' then (d->>'width_cm')::numeric else width_cm end,
      height_cm=case when d?'height_cm' then (d->>'height_cm')::numeric else height_cm end
      where id=prod.id returning * into prod;
    return jsonb_build_object('product',to_jsonb(prod));

  elsif p_action='variant_save' then
    if d-array['id','product_id','sku','title','price','stock','weight_kg','length_cm','width_cm','height_cm','published','version']<>'{}' or
       jsonb_typeof(d->'price')<>'number' or jsonb_typeof(d->'stock')<>'number' or jsonb_typeof(d->'weight_kg')<>'number' or
       jsonb_typeof(d->'published')<>'boolean' or (d->>'price')::numeric<>trunc((d->>'price')::numeric) or (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) then
      raise sqlstate 'PT400' using message='Thông tin biến thể SKU không hợp lệ.';
    end if;
    select * into prod from public.delivery_market_products where id=(d->>'product_id')::uuid for share;
    if not found or not public.delivery_market_can_access_shop(prod.shop_id,auth.uid(),'manager') then
      raise sqlstate 'PT403' using message='Không có quyền quản lý biến thể sản phẩm này.';
    end if;
    variant_key:=coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into prev_var from public.delivery_market_variants where id=variant_key for update;
    if prev_var.id is not null and (prev_var.product_id<>prod.id or prev_var.version is distinct from (d->>'version')::integer) then
      raise sqlstate 'PT409' using message='Biến thể đã thay đổi. Hãy tải lại.';
    end if;
    insert into public.delivery_market_variants(id,product_id,sku,title,price,stock,weight_kg,length_cm,width_cm,height_cm,published)
      values(variant_key,prod.id,btrim(d->>'sku'),btrim(d->>'title'),(d->>'price')::integer,(d->>'stock')::integer,(d->>'weight_kg')::numeric,
        coalesce((d->>'length_cm')::numeric,0),coalesce((d->>'width_cm')::numeric,0),coalesce((d->>'height_cm')::numeric,0),(d->>'published')::boolean)
      on conflict(id) do update set sku=excluded.sku,title=excluded.title,price=excluded.price,stock=excluded.stock,
        weight_kg=excluded.weight_kg,length_cm=excluded.length_cm,width_cm=excluded.width_cm,height_cm=excluded.height_cm,
        published=excluded.published,version=delivery_market_variants.version+1,updated_at=now() returning * into var_row;
    if var_row.stock<>coalesce(prev_var.stock,0) then
      insert into public.delivery_market_stock(product_id,variant_id,actor_id,delta,reason)
        values(prod.id,var_row.id,auth.uid(),var_row.stock-coalesce(prev_var.stock,0),'merchant_variant_adjust');
    end if;
    return jsonb_build_object('variant',to_jsonb(var_row));

  elsif p_action='voucher_save' then
    if d-array['id','shop_id','code','title','discount_kind','discount_value','max_discount','min_subtotal','budget_total','per_user_limit','starts_at','ends_at','active','version']<>'{}' then
      raise sqlstate 'PT400' using message='Thông tin mã giảm giá không hợp lệ.';
    end if;
    if d ? 'shop_id' and d->'shop_id' is not null and jsonb_typeof(d->'shop_id')='string' then
      if not public.delivery_market_can_access_shop((d->>'shop_id')::uuid,auth.uid(),'manager') and not op then
        raise sqlstate 'PT403' using message='Không có quyền tạo mã giảm giá cho cửa hàng này.';
      end if;
    elsif not op then
      raise sqlstate 'PT403' using message='Chỉ quản trị viên được tạo mã giảm giá toàn sàn.';
    end if;
    v_id:=coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into voucher_row from public.delivery_market_vouchers where id=v_id for update;
    if voucher_row.id is not null then
      if voucher_row.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Mã giảm giá đã thay đổi.'; end if;
      if (d->>'budget_total')::bigint < voucher_row.budget_used then raise sqlstate 'PT409' using message='Ngân sách mới thấp hơn mức đã sử dụng.'; end if;
    end if;
    insert into public.delivery_market_vouchers(id,code,shop_id,title,discount_kind,discount_value,max_discount,min_subtotal,budget_total,per_user_limit,starts_at,ends_at,active,created_by)
      values(v_id,upper(btrim(d->>'code')),nullif(d->>'shop_id','')::uuid,btrim(d->>'title'),d->>'discount_kind',
        (d->>'discount_value')::integer,(d->>'max_discount')::integer,coalesce((d->>'min_subtotal')::integer,0),
        (d->>'budget_total')::bigint,coalesce((d->>'per_user_limit')::integer,1),(d->>'starts_at')::timestamptz,
        (d->>'ends_at')::timestamptz,coalesce((d->>'active')::boolean,true),auth.uid())
      on conflict(id) do update set title=excluded.title,discount_kind=excluded.discount_kind,discount_value=excluded.discount_value,
        max_discount=excluded.max_discount,min_subtotal=excluded.min_subtotal,budget_total=excluded.budget_total,
        per_user_limit=excluded.per_user_limit,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active,
        version=delivery_market_vouchers.version+1,updated_at=now() returning * into voucher_row;
    if op then insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'voucher_save',voucher_row.id,to_jsonb(voucher_row)); end if;
    return jsonb_build_object('voucher',to_jsonb(voucher_row));

  elsif p_action='flash_sale_save' then
    if d-array['id','product_id','sale_price','allocated_stock','per_user_limit','starts_at','ends_at','active','version']<>'{}' then
      raise sqlstate 'PT400' using message='Thông tin Flash Sale không hợp lệ.';
    end if;
    select * into prod from public.delivery_market_products where id=(d->>'product_id')::uuid for share;
    if not found or (not public.delivery_market_can_access_shop(prod.shop_id,auth.uid(),'manager') and not op) then
      raise sqlstate 'PT403' using message='Không có quyền cấu hình Flash Sale cho sản phẩm này.';
    end if;
    if (d->>'sale_price')::integer >= prod.price then raise sqlstate 'PT400' using message='Giá Flash Sale phải nhỏ hơn giá niêm yết.'; end if;
    fs_id:=coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into flash_row from public.delivery_market_flash_sales where id=fs_id for update;
    if flash_row.id is not null then
      if flash_row.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Flash Sale đã thay đổi.'; end if;
      if (d->>'allocated_stock')::integer < flash_row.sold_stock then raise sqlstate 'PT409' using message='Số lượng phân bổ thấp hơn mức đã bán.'; end if;
    end if;
    insert into public.delivery_market_flash_sales(id,product_id,shop_id,sale_price,allocated_stock,per_user_limit,starts_at,ends_at,active)
      values(fs_id,prod.id,prod.shop_id,(d->>'sale_price')::integer,(d->>'allocated_stock')::integer,
        coalesce((d->>'per_user_limit')::integer,2),(d->>'starts_at')::timestamptz,(d->>'ends_at')::timestamptz,coalesce((d->>'active')::boolean,true))
      on conflict(id) do update set sale_price=excluded.sale_price,allocated_stock=excluded.allocated_stock,
        per_user_limit=excluded.per_user_limit,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active,
        version=delivery_market_flash_sales.version+1,updated_at=now() returning * into flash_row;
    return jsonb_build_object('flash_sale',to_jsonb(flash_row));

  elsif p_action in ('cart','cart_set') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    insert into public.delivery_market_carts(user_id) values(auth.uid()) on conflict do nothing;
    select version into cart_version from public.delivery_market_carts where user_id=auth.uid() for update;
    if p_action='cart_set' then
      if d-array['product_id','variant_id','line_id','selected_options','quantity','version']<>'{}' or
        jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) or
        (d->>'quantity')::numeric not between 0 and 99 then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
      if cart_version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy tải lại.'; end if;
      qty:=(d->>'quantity')::integer; product_key:=(d->>'product_id')::uuid;
      variant_key:=nullif(d->>'variant_id','')::uuid;
      line_key:=(d->>'line_id')::uuid; selected:=coalesce(d->'selected_options','[]');
      if product_key is null then raise sqlstate 'PT400' using message='Thiếu sản phẩm.'; end if;
      if line_key is not null then
        select c.selected_options,c.variant_id into selected,variant_key from public.delivery_market_cart_items c
          where c.user_id=auth.uid() and c.line_id=line_key and c.product_id=product_key;
        if not found then raise sqlstate 'PT409' using message='Dòng giỏ hàng đã thay đổi. Hãy tải lại.'; end if;
        if (d?'selected_options' and d->'selected_options' is distinct from selected) or
           (d?'variant_id' and nullif(d->>'variant_id','')::uuid is distinct from variant_key) then
          raise sqlstate 'PT409' using message='Không thể đổi lựa chọn của dòng giỏ hàng.'; end if;
      end if;
      if qty=0 then
        if line_key is null then
          selection:=public.delivery_market_selection_v2(product_key,selected,variant_key,1,auth.uid());
          line_key:=(selection->>'line_id')::uuid;
        end if;
        delete from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key and product_id=product_key;
      else
        select * into prod from public.delivery_market_products where id=product_key for share;
        select * into sh from public.delivery_market_shops where id=prod.shop_id;
        if prod.id is null or not prod.published or sh.status<>'active' or sh.paused or (not sh.is_showcase and sh.owner_id=auth.uid()) or
          not public.delivery_market_is_open(prod.sale_schedule) or not public.delivery_market_is_open(sh.opening_schedule) or
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and (sh.is_showcase or public.delivery_cloud_has_membership(user_id,'merchant')) and not blocked) then
          raise sqlstate 'PT409' using message='Sản phẩm không thể mua hoặc không đủ tồn kho.'; end if;
        selection:=public.delivery_market_selection_v2(product_key,selected,variant_key,qty,auth.uid());
        line_key:=(selection->>'line_id')::uuid;
        if variant_key is not null then
          select * into var_row from public.delivery_market_variants where id=variant_key and product_id=product_key and published for share;
          select qty+coalesce(sum(quantity),0) into aggregate_qty from public.delivery_market_cart_items
            where user_id=auth.uid() and variant_id=variant_key and line_id<>line_key;
          if var_row.id is null or aggregate_qty>var_row.stock or aggregate_qty>99 then
            raise sqlstate 'PT409' using message='Tổng số lượng biến thể vượt tồn kho hoặc giới hạn 99.';
          end if;
        else
          select qty+coalesce(sum(quantity),0) into aggregate_qty from public.delivery_market_cart_items
            where user_id=auth.uid() and product_id=product_key and variant_id is null and line_id<>line_key;
          if aggregate_qty>prod.stock or aggregate_qty>99 then raise sqlstate 'PT409' using message='Tổng số lượng các lựa chọn vượt tồn kho hoặc giới hạn 99.'; end if;
        end if;
        if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key) and
          (select count(*) from public.delivery_market_cart_items where user_id=auth.uid())>=50 then raise sqlstate 'PT400' using message='Giỏ hàng hỗ trợ tối đa 50 dòng.'; end if;
        insert into public.delivery_market_cart_items(user_id,product_id,variant_id,quantity,line_id,selected_options)
          values(auth.uid(),product_key,variant_key,qty,line_key,selection->'selected_options')
          on conflict(user_id,line_id) do update set quantity=excluded.quantity;
      end if;
      update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    end if;
    return public.delivery_market_configured_cart();

  elsif p_action in ('quote','checkout') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    if p_action='quote' then
      if d-array['address_id','cart_version','address_version','buyer_note','service_type','payment_method','scheduled_at','prefer_ev','require_pod','require_otp','voucher_code','use_coins']<>'{}' or
        (d?'cart_version' and (jsonb_typeof(d->'cart_version') is distinct from 'number' or
          (d->>'cart_version')::numeric<>trunc((d->>'cart_version')::numeric))) or
        (d?'address_version' and (jsonb_typeof(d->'address_version') is distinct from 'number' or
          (d->>'address_version')::numeric<>trunc((d->>'address_version')::numeric))) then
        raise sqlstate 'PT400' using message='Yêu cầu báo giá không hợp lệ.'; end if;
      snapshot:=public.delivery_market_snapshot_v2((d->>'address_id')::uuid,d-array['address_id','cart_version','address_version']);
      if d?'cart_version' and d->'cart_version' is distinct from snapshot->'cart_version' then
        raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy kiểm tra lại.'; end if;
      if d?'address_version' and d->'address_version' is distinct from snapshot->'address_version' then
        raise sqlstate 'PT409' using message='Địa chỉ đã thay đổi. Hãy kiểm tra lại địa chỉ nhận hàng.'; end if;
      insert into public.delivery_market_quotes(owner_id,snapshot) values(auth.uid(),snapshot) returning * into quote;
      return jsonb_build_object('quote',to_jsonb(quote)-'owner_id');
    end if;

    if d-array['quote_id','request_key']<>'{}' or not(d ?& array['quote_id','request_key']) then raise sqlstate 'PT400' using message='Yêu cầu đặt hàng không hợp lệ.'; end if;
    select * into purchase from public.delivery_market_purchases where owner_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if purchase.quote_id<>(d->>'quote_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho báo giá khác.'; end if;
      return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');
    end if;
    select * into quote from public.delivery_market_quotes where delivery_market_quotes.id=(d->>'quote_id')::uuid and owner_id=auth.uid() for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy báo giá.'; end if;
    select * into purchase from public.delivery_market_purchases where quote_id=quote.id and owner_id=auth.uid();
    if found then return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key'); end if;
    if quote.expires_at<=now() then raise sqlstate 'PT409' using message='Báo giá đã hết hạn. Hãy lấy báo giá mới.'; end if;

    perform 1 from public.delivery_market_shops where delivery_market_shops.id in
      (select (g->>'shop_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by delivery_market_shops.id for share;
    perform 1 from public.delivery_cloud_accounts where user_id in
      (select (g->>'merchant_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by user_id for share;
    perform 1 from public.delivery_market_products where delivery_market_products.id in
      (select (i->>'product_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i) order by delivery_market_products.id for update;
    perform 1 from public.delivery_market_variants where delivery_market_variants.id in
      (select (i->>'variant_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i where i ? 'variant_id' and jsonb_typeof(i->'variant_id')='string') order by delivery_market_variants.id for update;
    if quote.snapshot ? 'voucher_id' and jsonb_typeof(quote.snapshot->'voucher_id')='string' then
      perform 1 from public.delivery_market_vouchers where id=(quote.snapshot->>'voucher_id')::uuid for update;
    end if;
    perform 1 from public.delivery_market_flash_sales where id in
      (select (i->>'flash_sale_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i where i ? 'flash_sale_id' and jsonb_typeof(i->'flash_sale_id')='string') order by id for update;
    if coalesce((quote.snapshot->>'coin_discount')::bigint,0)>0 then
      perform 1 from public.delivery_market_coin_wallets where user_id=auth.uid() for update;
    end if;
    perform 1 from public.delivery_cloud_addresses where delivery_cloud_addresses.id=(quote.snapshot->>'address_id')::uuid for share;
    perform 1 from public.delivery_cloud_pricing where delivery_cloud_pricing.id for share;

    snapshot:=public.delivery_market_snapshot_v2((quote.snapshot->>'address_id')::uuid,coalesce(quote.snapshot->'checkout_options','{}'::jsonb));
    if snapshot<>quote.snapshot then raise sqlstate 'PT409' using message='Giá, khuyến mãi, giỏ hàng hoặc địa chỉ đã thay đổi. Hãy xác nhận báo giá mới.'; end if;

    insert into public.delivery_market_purchases(owner_id,request_key,quote_id,snapshot,total,payment_method)
      values(auth.uid(),(d->>'request_key')::uuid,quote.id,snapshot,(snapshot->>'total')::integer,coalesce(snapshot->>'payment_method','cod'))
      returning * into purchase;

    coin_total:=coalesce((snapshot->>'coin_discount')::bigint,0);
    coin_rem:=coin_total;
    if coin_total>0 then
      update public.delivery_market_coin_wallets set balance=balance-coin_total,updated_at=now()
        where user_id=auth.uid() and balance>=coin_total;
      if not found then raise sqlstate 'PT409' using message='Số dư xu không đủ.'; end if;
      insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
        values(auth.uid(),-coin_total,'redeem_checkout',purchase.id);
    end if;

    sh_cnt:=jsonb_array_length(snapshot->'shops');
    for group_row in select * from jsonb_array_elements(snapshot->'shops') loop
      sh_idx:=sh_idx+1;
      if coin_rem>0 then
        if sh_idx=sh_cnt then sh_coin:=coin_rem;
        else sh_coin:=least(coin_rem,floor(coin_total*(group_row->>'subtotal')::numeric/greatest(1,(snapshot->>'goods_subtotal')::numeric))::bigint);
        end if;
        coin_rem:=greatest(0,coin_rem-sh_coin);
        group_row:=group_row||jsonb_build_object('coin_share',sh_coin);
      end if;
      insert into public.delivery_market_shop_orders(purchase_id,shop_id,owner_id,merchant_id,snapshot)
        values(purchase.id,(group_row->>'shop_id')::uuid,auth.uid(),(group_row->>'merchant_id')::uuid,group_row) returning * into so;
      for item in select * from jsonb_array_elements(group_row->'items') loop
        if item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then
          update public.delivery_market_variants set stock=stock-(item->>'quantity')::integer,version=version+1,updated_at=now()
            where id=(item->>'variant_id')::uuid and stock>=(item->>'quantity')::integer;
          if not found then raise sqlstate 'PT409' using message='Biến thể không đủ tồn kho.'; end if;
          insert into public.delivery_market_stock(product_id,variant_id,actor_id,delta,reason,reference_id)
            values((item->>'product_id')::uuid,(item->>'variant_id')::uuid,auth.uid(),-(item->>'quantity')::integer,'purchase_allocate',so.id);
        else
          update public.delivery_market_products set stock=stock-(item->>'quantity')::integer,version=version+1,updated_at=now()
            where delivery_market_products.id=(item->>'product_id')::uuid and stock>=(item->>'quantity')::integer;
          if not found then raise sqlstate 'PT409' using message='Sản phẩm không đủ tồn kho.'; end if;
          insert into public.delivery_market_stock(product_id,actor_id,delta,reason,reference_id)
            values((item->>'product_id')::uuid,auth.uid(),-(item->>'quantity')::integer,'purchase_allocate',so.id);
        end if;
        if item ? 'flash_sale_id' and jsonb_typeof(item->'flash_sale_id')='string' then
          update public.delivery_market_flash_sales set sold_stock=sold_stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
            where id=(item->>'flash_sale_id')::uuid and active and starts_at<=now() and ends_at>now()
              and sold_stock+(item->>'quantity')::integer<=allocated_stock;
          if not found then raise sqlstate 'PT409' using message='Suất Flash Sale đã hết.'; end if;
          insert into public.delivery_market_flash_claims(flash_sale_id,order_id,user_id,quantity)
            values((item->>'flash_sale_id')::uuid,so.id,auth.uid(),(item->>'quantity')::integer);
        end if;
      end loop;

      if snapshot ? 'voucher_id' and jsonb_typeof(snapshot->'voucher_id')='string' then
        select * into voucher_row from public.delivery_market_vouchers where id=(snapshot->>'voucher_id')::uuid;
        if (voucher_row.shop_id is not null and voucher_row.shop_id=so.shop_id) or (voucher_row.shop_id is null and sh_idx=1) then
          update public.delivery_market_vouchers set budget_used=budget_used+(snapshot->>'voucher_discount')::bigint,version=version+1,updated_at=now()
            where id=voucher_row.id and active and budget_used+(snapshot->>'voucher_discount')::bigint<=budget_total;
          if not found then raise sqlstate 'PT409' using message='Ngân sách mã giảm giá vừa hết.'; end if;
          insert into public.delivery_market_voucher_usages(voucher_id,purchase_id,order_id,user_id,discount_amount)
            values(voucher_row.id,purchase.id,so.id,auth.uid(),(snapshot->>'voucher_discount')::integer);
        end if;
      end if;

      insert into public.delivery_market_events(order_id,actor_id,action) values(so.id,auth.uid(),'created');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'new_order');

      if coalesce(purchase.payment_method, 'cod') = 'cod' then
        perform public.delivery_showcase_auto_dispatch_order(so.id, auth.uid());
      end if;
    end loop;

    delete from public.delivery_market_cart_items where user_id=auth.uid();
    update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');

  elsif p_action='orders' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select o.*,p.payment_status,p.payment_method,del.status as delivery_status,del.tracking_code,
        coalesce((select jsonb_agg(jsonb_build_object('parcel_index',ms.parcel_index,'delivery_id',ms.delivery_id,'tracking_code',co.tracking_code,'status',co.status,'weight_kg',ms.weight_kg,'cod_amount',ms.cod_amount) order by ms.parcel_index)
          from public.delivery_market_shipments ms join public.delivery_cloud_orders co on co.id=ms.delivery_id where ms.order_id=o.id),'[]'::jsonb) as shipments
      from public.delivery_market_shop_orders o join public.delivery_market_purchases p on p.id=o.purchase_id
      left join public.delivery_cloud_orders del on del.id=o.delivery_id
      where (case when d->>'workspace'='merchant' then public.delivery_market_can_access_shop(o.shop_id,auth.uid(),'staff') else o.owner_id=auth.uid() end)
        and (not(d ? 'after') or o.id>(d->>'after')::uuid) order by o.id limit 50) x;
    return jsonb_build_object('orders',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);

  elsif p_action in ('order_action','order_shipment_split','messages','message_send') then
    select * into so from public.delivery_market_shop_orders where delivery_market_shop_orders.id=(d->>'order_id')::uuid
      and (owner_id=auth.uid() or public.delivery_market_can_access_shop(shop_id,auth.uid(),'staff')) for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;

    if p_action='order_shipment_split' then
      if not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') then
        raise sqlstate 'PT403' using message='Chỉ chủ cửa hàng hoặc quản lý được tách kiện giao hàng.';
      end if;
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if so.state<>'accepted' or so.delivery_id is not null or exists(select 1 from public.delivery_market_shipments where order_id=so.id) then
        raise sqlstate 'PT409' using message='Chỉ đơn đã nhận và chưa tạo vận đơn mới được tách kiện.';
      end if;
      select * into purchase from public.delivery_market_purchases where id=so.purchase_id;
      if purchase.payment_method='prepaid' and purchase.payment_status<>'PAID' then
        raise sqlstate 'PT409' using message='Đơn trả trước chưa thanh toán thành công.';
      end if;
      if jsonb_typeof(d->'parcels')<>'array' or jsonb_array_length(d->'parcels') not between 2 and 10 then
        raise sqlstate 'PT400' using message='Tách kiện cần từ 2 đến 10 kiện hàng.';
      end if;
      expected_cod:=case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx:=idx+1;
        parcel_weight:=coalesce((parcel->>'weight_kg')::numeric,0);
        if parcel_weight<=0 or parcel_weight>500 or jsonb_typeof(coalesce(parcel->'cod_amount','0'::jsonb))<>'number' or
           (parcel->>'cod_amount')::numeric<0 or (parcel->>'cod_amount')::numeric<>trunc((parcel->>'cod_amount')::numeric) then
          raise sqlstate 'PT400' using message='Khối lượng hoặc COD từng kiện không hợp lệ.';
        end if;
        split_cod:=split_cod+coalesce((parcel->>'cod_amount')::bigint,0);
      end loop;
      if split_cod<>expected_cod then
        raise sqlstate 'PT409' using message='Tổng COD các kiện phải khớp số tiền cần thu của đơn.';
      end if;
      idx:=0;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx:=idx+1;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id,'parcel_index',idx),
            jsonb_set(jsonb_set(so.snapshot->'details','{weight_kg}',parcel->'weight_kg'),'{cod_amount}',coalesce(parcel->'cod_amount','0'::jsonb)),
            (so.snapshot->>'distance_meters')::integer,
            case when idx=1 then (so.snapshot->>'shipping_fee')::integer else 0 end,
            coalesce((parcel->>'cod_amount')::integer,0),(so.snapshot->>'pricing_version')::integer,true)
          returning * into shipment;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code) on conflict do nothing;
        insert into public.delivery_live_members(room_id,user_id,role) values(shipment.tracking_code,so.owner_id,'customer') on conflict(room_id,user_id) do nothing;
        insert into public.delivery_live_members(room_id,user_id,role) values(shipment.tracking_code,so.merchant_id,'merchant') on conflict(room_id,user_id) do nothing;
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        insert into public.delivery_market_shipments(order_id,delivery_id,parcel_index,items,weight_kg,cod_amount)
          values(so.id,shipment.id,idx,coalesce(parcel->'items','[]'::jsonb),(parcel->>'weight_kg')::numeric,coalesce((parcel->>'cod_amount')::integer,0));
        if idx=1 then so.delivery_id:=shipment.id; end if;
      end loop;
      update public.delivery_market_shop_orders set state='ready',delivery_id=so.delivery_id,version=version+1,updated_at=now()
        where id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'ready_split','Tách '||idx||' kiện vận chuyển');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'ready');
      return jsonb_build_object('order',to_jsonb(so));
    end if;

    if p_action='order_action' then
      requested:=d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') then
        raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.';
      end if;
      select * into purchase from public.delivery_market_purchases where id=so.purchase_id;
      if requested in ('accept','ready') and purchase.payment_method='prepaid' and purchase.payment_status<>'PAID' then
        raise sqlstate 'PT409' using message='Đơn trả trước cần khách thanh toán thành công trước khi xác nhận.';
      end if;
      if requested='accept' and so.state='pending' then so.state:='accepted';
      elsif requested='ready' and so.state='accepted' then
        expected_cod:=case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id),so.snapshot->'details',
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,
            expected_cod::integer,(so.snapshot->>'pricing_version')::integer,true) returning * into shipment;
        if coalesce((so.snapshot->'details'->>'require_otp')::boolean,false) then
          insert into public.delivery_cloud_order_secrets(order_id,otp_code,otp_hash)
            select shipment.id,otp_code,encode(sha256(convert_to(otp_code,'UTF8')),'hex')
            from (select ((get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),0)*65536 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),1)*256 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),2)) % 900000 + 100000)::text as otp_code) g;
        end if;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code) on conflict do nothing;
        insert into public.delivery_live_members(room_id,user_id,role) values(shipment.tracking_code,so.owner_id,'customer') on conflict(room_id,user_id) do nothing;
        insert into public.delivery_live_members(room_id,user_id,role) values(shipment.tracking_code,so.merchant_id,'merchant') on conflict(room_id,user_id) do nothing;
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        so.state:='ready'; so.delivery_id:=shipment.id;
      elsif requested='cancel' and so.state in ('pending','accepted') and length(btrim(coalesce(d->>'reason',''))) between 3 and 500 and
        (public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') or (so.owner_id=auth.uid() and so.state='pending')) then
        perform public.delivery_market_release_order_allocations(so,auth.uid(),'user','cancel_release');
        so.state:='cancelled'; so.reason:=btrim(d->>'reason');
        if purchase.payment_status='PAID' then
          update public.delivery_market_purchases set payment_status='REVIEW' where id=purchase.id;
        end if;
      else raise sqlstate 'PT409' using message='Không thể thực hiện thao tác ở trạng thái này.';
      end if;
      update public.delivery_market_shop_orders set state=so.state,delivery_id=so.delivery_id,reason=so.reason,
        version=version+1,updated_at=now() where delivery_market_shop_orders.id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),requested,so.reason);
      insert into public.delivery_market_notifications(user_id,order_id,kind)
        values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,requested);
      return jsonb_build_object('order',to_jsonb(so));
    end if;

    if p_action='message_send' then
      if jsonb_typeof(d->'body') is distinct from 'string' or length(btrim(d->>'body')) not between 1 and 2000 or d->>'request_key' is null then
        raise sqlstate 'PT400' using message='Nội dung tin nhắn không hợp lệ.'; end if;
      if d ? 'attachments' then
        if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>4 then
          raise sqlstate 'PT400' using message='Tối đa 4 tệp đính kèm mỗi tin nhắn.';
        end if;
        for att_name in select jsonb_array_elements_text(d->'attachments') loop
          if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='chat') then
            raise sqlstate 'PT403' using message='Tệp đính kèm không thuộc cuộc hội thoại này.';
          end if;
        end loop;
        att_list:=d->'attachments';
      end if;
      perform pg_advisory_xact_lock(hashtextextended('message:'||auth.uid()::text,0));
      select * into msg from public.delivery_market_messages where actor_id=auth.uid() and request_key=(d->>'request_key')::uuid;
      if msg.id is not null then
        if msg.order_id<>so.id or msg.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Mã tin nhắn đã được dùng.'; end if;
      else
        if (select count(*) from public.delivery_market_messages where actor_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then
          raise sqlstate 'PT409' using message='Bạn gửi quá nhiều tin nhắn. Vui lòng chờ.'; end if;
        insert into public.delivery_market_messages(order_id,actor_id,body,attachments,request_key)
          values(so.id,auth.uid(),btrim(d->>'body'),att_list,(d->>'request_key')::uuid);
        insert into public.delivery_market_notifications(user_id,order_id,kind)
          values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'message');
      end if;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x)-'request_key' order by x.created_at,x.id),'[]') into result from
      (select * from public.delivery_market_messages where order_id=so.id and (not(d ? 'before') or
        (created_at,id)<((d->>'before')::timestamptz,coalesce((d->>'before_id')::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by created_at desc,id desc limit 50) x;
    return jsonb_build_object('messages',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('before',result->0->>'created_at','before_id',result->0->>'id') end,
      'events',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from
        (select * from public.delivery_market_events where order_id=so.id order by created_at desc,id desc limit 50) x),'[]'));

  elsif p_action in ('notifications','notification_read') then
    if p_action='notification_read' then
      update public.delivery_market_notifications set read_at=coalesce(read_at,now()) where delivery_market_notifications.id=(d->>'id')::uuid and user_id=auth.uid();
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into result from
      (select * from public.delivery_market_notifications where user_id=auth.uid() and (not(d ? 'before') or
        (created_at,id)<((d->>'before')::timestamptz,coalesce((d->>'before_id')::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by created_at desc,id desc limit 50) x;
    return jsonb_build_object('notifications',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('before',result->49->>'created_at','before_id',result->49->>'id') end);
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end $$;

revoke all on function public.delivery_marketplace(text, jsonb) from public, anon;
grant execute on function public.delivery_marketplace(text, jsonb) to authenticated;

-- Wrap delivery_market_operations for showcase product_details, favorites, shop_details & shop_follow_set
create or replace function public.delivery_market_operations(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  a public.delivery_cloud_accounts;
  sh public.delivery_market_shops;
  prod public.delivery_market_products;
  res jsonb;
  op boolean;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op := public.delivery_is_operator();
  if a.blocked or (a.user_id is null and not op) then raise sqlstate 'PT403' using message='Cần tài khoản đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.'; end if;

  if p_action in ('favorites', 'favorite_set', 'product_details') then
    if p_action = 'favorite_set' then
      if jsonb_typeof(d->'enabled') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Lựa chọn không hợp lệ.'; end if;
      if (d->>'enabled')::boolean then
        if not exists(
          select 1 from public.delivery_market_products p
          join public.delivery_market_shops s on s.id = p.shop_id
          join public.delivery_cloud_accounts m on m.user_id = s.owner_id
          where p.id = (d->>'product_id')::uuid
            and p.published and s.status = 'active' and not s.paused and not m.blocked
            and (s.is_showcase or public.delivery_cloud_has_membership(m.user_id, 'merchant'))
        ) then
          raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.';
        end if;
        insert into public.delivery_market_favorites(user_id, product_id)
          values (auth.uid(), (d->>'product_id')::uuid) on conflict do nothing;
      else
        delete from public.delivery_market_favorites where user_id = auth.uid() and product_id = (d->>'product_id')::uuid;
      end if;
    end if;

    if p_action = 'product_details' then
      select p.* into prod from public.delivery_market_products p
        join public.delivery_market_shops s on s.id = p.shop_id
        join public.delivery_cloud_accounts m on m.user_id = s.owner_id
        where p.id = (d->>'product_id')::uuid
          and p.published and s.status = 'active' and not s.paused and not m.blocked
          and (s.is_showcase or public.delivery_cloud_has_membership(m.user_id, 'merchant'));
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
      return jsonb_build_object(
        'product', to_jsonb(prod) || jsonb_build_object(
          'available', (prod.stock > 0 or exists(select 1 from public.delivery_market_variants v where v.product_id = prod.id and v.published and v.stock > 0))
            and public.delivery_market_is_open(prod.sale_schedule)
            and exists(select 1 from public.delivery_market_shops where id = prod.shop_id and public.delivery_market_is_open(opening_schedule))
        ),
        'variants', coalesce((select jsonb_agg(to_jsonb(v) order by v.sku, v.id) from public.delivery_market_variants v where v.product_id = prod.id and v.published), '[]'::jsonb),
        'flash_sale', (select to_jsonb(fs) - 'version' from public.delivery_market_flash_sales fs
          where fs.product_id = prod.id and fs.active and fs.starts_at <= now() and fs.ends_at > now() and fs.sold_stock < fs.allocated_stock
          order by fs.sale_price asc, fs.id asc limit 1),
        'favorite', exists(select 1 from public.delivery_market_favorites where user_id = auth.uid() and product_id = prod.id),
        'shop_following', exists(select 1 from public.delivery_market_shop_follows where user_id = auth.uid() and shop_id = prod.shop_id),
        'shop_followers', (select count(*) from public.delivery_market_shop_follows where shop_id = prod.shop_id),
        'vouchers', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', v.id, 'code', v.code, 'shop_id', v.shop_id, 'title', v.title,
              'discount_kind', v.discount_kind, 'discount_value', v.discount_value,
              'max_discount', v.max_discount, 'min_subtotal', v.min_subtotal, 'ends_at', v.ends_at
            ) || case when v.owner_user_id is not null then jsonb_build_object('personal', true) else '{}'::jsonb end
            order by v.created_at desc
          )
          from public.delivery_market_vouchers v
          where v.active and v.starts_at <= now() and v.ends_at > now() and v.budget_used < v.budget_total
            and (v.shop_id is null or v.shop_id = prod.shop_id)
            and (v.owner_user_id is null or v.owner_user_id = auth.uid())
        ), '[]'::jsonb),
        'reviews', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc) from
          (select id, rating, body, reply, replied_at, created_at from public.delivery_market_reviews where product_id = prod.id and not hidden order by created_at desc, id desc limit 50) r), '[]'::jsonb)
      );
    end if;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) into res from (
      select p.*, s.name as shop_name, s.is_showcase, s.category_group
      from public.delivery_market_favorites fav
      join public.delivery_market_products p on p.id = fav.product_id
      join public.delivery_market_shops s on s.id = p.shop_id
      join public.delivery_cloud_accounts m on m.user_id = s.owner_id
      where fav.user_id = auth.uid() and p.published and s.status = 'active' and not s.paused and not m.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(m.user_id, 'merchant'))
        and (coalesce(d->>'search', '') = '' or strpos(lower(p.name || ' ' || s.name || ' ' || p.sku), lower(d->>'search')) > 0)
        and (not(d ? 'after') or p.id > (d->>'after')::uuid)
      order by p.id limit 50
    ) x;
    return jsonb_build_object('products', res, 'next', case when jsonb_array_length(res) = 50 then jsonb_build_object('after', res->49->>'id') end);

  elsif p_action = 'shop_details' then
    select s.* into sh from public.delivery_market_shops s
      join public.delivery_cloud_accounts m on m.user_id = s.owner_id
      where s.id = (d->>'shop_id')::uuid and s.status = 'active' and not m.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(m.user_id, 'merchant'));
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy cửa hàng.'; end if;
    return jsonb_build_object(
      'shop', jsonb_build_object(
        'id', sh.id, 'name', sh.name, 'description', sh.description, 'address', sh.address, 'paused', sh.paused,
        'opening_schedule', sh.opening_schedule, 'open', not sh.paused and public.delivery_market_is_open(sh.opening_schedule),
        'banner_url', sh.banner_url, 'service_radius_km', sh.service_radius_km,
        'is_showcase', sh.is_showcase, 'category_group', sh.category_group
      ),
      'followers', (select count(*) from public.delivery_market_shop_follows where shop_id = sh.id),
      'following', exists(select 1 from public.delivery_market_shop_follows where user_id = auth.uid() and shop_id = sh.id),
      'rating_avg', coalesce((select round(avg(rating)::numeric, 2) from public.delivery_partner_reviews where target_kind = 'shop' and shop_id = sh.id and not hidden), 0),
      'rating_count', (select count(*) from public.delivery_partner_reviews where target_kind = 'shop' and shop_id = sh.id and not hidden),
      'partner_reviews', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc) from
        (select id, rating, body, reply, replied_at, created_at from public.delivery_partner_reviews where target_kind = 'shop' and shop_id = sh.id and not hidden order by created_at desc, id desc limit 30) r), '[]'::jsonb),
      'vouchers', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', v.id, 'code', v.code, 'shop_id', v.shop_id, 'title', v.title,
            'discount_kind', v.discount_kind, 'discount_value', v.discount_value,
            'max_discount', v.max_discount, 'min_subtotal', v.min_subtotal, 'ends_at', v.ends_at
          ) || case when v.owner_user_id is not null then jsonb_build_object('personal', true) else '{}'::jsonb end
          order by v.created_at desc
        )
        from public.delivery_market_vouchers v
        where v.active and v.starts_at <= now() and v.ends_at > now() and v.budget_used < v.budget_total
          and (v.shop_id is null or v.shop_id = sh.id)
          and (v.owner_user_id is null or v.owner_user_id = auth.uid())
      ), '[]'::jsonb)
    );

  elsif p_action = 'shop_follow_set' then
    if jsonb_typeof(d->'enabled') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Lựa chọn theo dõi không hợp lệ.'; end if;
    select s.* into sh from public.delivery_market_shops s
      join public.delivery_cloud_accounts m on m.user_id = s.owner_id
      where s.id = (d->>'shop_id')::uuid and s.status = 'active' and not m.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(m.user_id, 'merchant'));
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy cửa hàng.'; end if;
    if not sh.is_showcase and sh.owner_id = auth.uid() then
      raise sqlstate 'PT400' using message='Không thể tự theo dõi cửa hàng của mình.';
    end if;
    if (d->>'enabled')::boolean then
      insert into public.delivery_market_shop_follows(user_id, shop_id) values (auth.uid(), sh.id) on conflict do nothing;
    else
      delete from public.delivery_market_shop_follows where user_id = auth.uid() and shop_id = sh.id;
    end if;
    return jsonb_build_object('following', (d->>'enabled')::boolean, 'followers', (select count(*) from public.delivery_market_shop_follows where shop_id = sh.id));
  end if;

  res := public.delivery_market_operations_core(p_action, p_payload);
  if p_action = 'vouchers' and jsonb_typeof(res->'vouchers') = 'array' then
    res := jsonb_set(
      res,
      '{vouchers}',
      coalesce((
        select jsonb_agg(
          elem || case when v.owner_user_id is not null then jsonb_build_object('personal', true) else '{}'::jsonb end
          order by ord
        )
        from jsonb_array_elements(res->'vouchers') with ordinality as arr(elem, ord)
        join public.delivery_market_vouchers v on v.id = (elem->>'id')::uuid
        where v.owner_user_id is null or v.owner_user_id = auth.uid()
      ), '[]'::jsonb)
    );
  end if;
  return res;
end $$;

revoke all on function public.delivery_market_operations(text, jsonb) from public, anon;
grant execute on function public.delivery_market_operations(text, jsonb) to authenticated;

-- Update delivery_market_browse to surface showcase shops, featured shop cards & exact public shop projection
create or replace function public.delivery_market_browse(p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; result jsonb; categories jsonb; shop jsonb; shop_meta jsonb; featured_shops jsonb:='[]'::jsonb;
  ordering text:=coalesce(d->>'sort','default');
  low integer:=0; high integer:=10000000; last_value jsonb;
  b_lat float8; b_lng float8; has_coords boolean:=false;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if not exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked) then
    raise sqlstate 'PT403' using message='Tài khoản chưa được xác minh hoặc đã bị khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 or
    d-array['search','category','shop_id','min_price','max_price','in_stock','sort','after','after_value','buyer_lat','buyer_lng']<>'{}' or
    ordering not in ('default','price_asc','price_desc','newest') then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
  if (d?'search' and (jsonb_typeof(d->'search')<>'string' or length(d->>'search')>160)) or
    (d?'category' and (jsonb_typeof(d->'category')<>'string' or length(d->>'category')>80)) or
    (d?'in_stock' and jsonb_typeof(d->'in_stock')<>'boolean') or
    ((d?'buyer_lat')<>(d?'buyer_lng')) then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
  if d?'buyer_lat' then
    if jsonb_typeof(d->'buyer_lat')<>'number' or jsonb_typeof(d->'buyer_lng')<>'number' or
       abs((d->>'buyer_lat')::float8)>90 or abs((d->>'buyer_lng')::float8)>180 then
      raise sqlstate 'PT400' using message='Tọa độ lọc cửa hàng không hợp lệ.';
    end if;
    b_lat:=(d->>'buyer_lat')::float8; b_lng:=(d->>'buyer_lng')::float8; has_coords:=true;
  end if;
  if d?'min_price' then
    if jsonb_typeof(d->'min_price')<>'number' or (d->>'min_price')::numeric not between 0 and 10000000 or
      (d->>'min_price')::numeric<>trunc((d->>'min_price')::numeric) then raise sqlstate 'PT400' using message='Giá tối thiểu không hợp lệ.'; end if;
    low:=(d->>'min_price')::integer;
  end if;
  if d?'max_price' then
    if jsonb_typeof(d->'max_price')<>'number' or (d->>'max_price')::numeric not between 0 and 10000000 or
      (d->>'max_price')::numeric<>trunc((d->>'max_price')::numeric) then raise sqlstate 'PT400' using message='Giá tối đa không hợp lệ.'; end if;
    high:=(d->>'max_price')::integer;
  end if;
  if low>high or (d?'after')<>(d?'after_value') or
    (d?'after_value' and (jsonb_typeof(d->'after_value')<>'number' or abs((d->>'after_value')::numeric)>3000000000000)) then
    raise sqlstate 'PT400' using message='Khoảng giá hoặc trang tiếp theo không hợp lệ.';
  end if;

  if d?'shop_id' then
    -- Keep exact 7-key projection on `shop` (verified by PostgreSQL acceptance tests); extra fields live in `shop_meta`
    select jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'address',s.address,'paused',s.paused,'opening_schedule',s.opening_schedule,'open',not s.paused and public.delivery_market_is_open(s.opening_schedule)),
           jsonb_build_object('banner_url',s.banner_url,'service_radius_km',s.service_radius_km,'is_showcase',s.is_showcase,'category_group',s.category_group,
             'followers',(select count(*) from public.delivery_market_shop_follows f where f.shop_id=s.id),
             'following',exists(select 1 from public.delivery_market_shop_follows f where f.shop_id=s.id and f.user_id=auth.uid()),
             'rating_avg',coalesce((select round(avg(rating)::numeric,2) from public.delivery_partner_reviews pr where pr.target_kind='shop' and pr.shop_id=s.id and not pr.hidden),0),
             'rating_count',(select count(*) from public.delivery_partner_reviews pr where pr.target_kind='shop' and pr.shop_id=s.id and not pr.hidden))
      into shop,shop_meta from public.delivery_market_shops s join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where s.id=(d->>'shop_id')::uuid and s.status='active' and not a.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(a.user_id,'merchant'));
    if shop is null then raise sqlstate 'PT404' using message='Cửa hàng không còn khả dụng.'; end if;
  else
    select coalesce(jsonb_agg(to_jsonb(sx) order by sx.is_showcase desc, sx.product_count desc, sx.id asc), '[]'::jsonb)
      into featured_shops
      from (
        select
          s.id, s.name, s.description, s.address, s.banner_url, s.category_group, s.is_showcase,
          not s.paused and public.delivery_market_is_open(s.opening_schedule) as open,
          (select count(*)::int from public.delivery_market_products p2 where p2.shop_id = s.id and p2.published) as product_count,
          coalesce((select round(avg(pr.rating)::numeric, 2) from public.delivery_partner_reviews pr where pr.target_kind = 'shop' and pr.shop_id = s.id and not pr.hidden), 4.9) as rating_avg
        from public.delivery_market_shops s
        join public.delivery_cloud_accounts a on a.user_id = s.owner_id
        where s.status = 'active' and not s.paused and not a.blocked
          and (s.is_showcase or public.delivery_cloud_has_membership(a.user_id, 'merchant'))
          and exists(select 1 from public.delivery_market_products p3 where p3.shop_id = s.id and p3.published)
        order by s.is_showcase desc, s.updated_at desc, s.id asc
        limit 16
      ) sx;
  end if;

  select coalesce(jsonb_agg(category order by category),'[]') into categories from (
    select distinct p.category from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(a.user_id,'merchant'))
        and (not(d?'shop_id') or s.id=(d->>'shop_id')::uuid) order by p.category limit 100
  ) c;

  with visible as (
    select p.*,s.name as shop_name,s.is_showcase,s.category_group,
      (p.stock>0 or exists(select 1 from public.delivery_market_variants v where v.product_id=p.id and v.published and v.stock>0))
        and public.delivery_market_is_open(p.sale_schedule) and public.delivery_market_is_open(s.opening_schedule) as available,
      (select count(*)::int from public.delivery_market_variants v where v.product_id=p.id and v.published) as variants_count,
      (select jsonb_build_object('id',fs.id,'sale_price',fs.sale_price,'allocated_stock',fs.allocated_stock,'sold_stock',fs.sold_stock,'ends_at',fs.ends_at)
        from public.delivery_market_flash_sales fs where fs.product_id=p.id and fs.active and fs.starts_at<=now() and fs.ends_at>now() and fs.sold_stock<fs.allocated_stock
        order by fs.sale_price asc,fs.id asc limit 1) as flash_sale,
      case ordering when 'price_asc' then p.price::numeric when 'price_desc' then -p.price::numeric
        when 'newest' then -extract(epoch from p.updated_at) else 0::numeric end as sort_value
      from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked
        and (s.is_showcase or public.delivery_cloud_has_membership(a.user_id,'merchant'))
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku||' '||s.category_group),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d?'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not has_coords or s.service_radius_km=0 or (
          6371000.0*2.0*asin(sqrt(least(1.0,power(sin(radians(b_lat-s.latitude)/2),2)+cos(radians(s.latitude))*cos(radians(b_lat))*power(sin(radians(b_lng-s.longitude)/2),2))))*1.3 <= s.service_radius_km*1000.0
        ))
        and p.price between low and high
        and (coalesce((d->>'in_stock')::boolean,false)=false or p.stock>0 or exists(select 1 from public.delivery_market_variants v where v.product_id=p.id and v.published and v.stock>0))
  ) select coalesce(jsonb_agg(to_jsonb(x) order by sort_value,id),'[]') into result from (
    select * from visible where not(d?'after') or (sort_value,id)>((d->>'after_value')::numeric,(d->>'after')::uuid)
      order by sort_value,id limit 50
  ) x;
  last_value:=result->49;
  return jsonb_build_object(
    'products',coalesce((select jsonb_agg(i-'sort_value' order by ord) from jsonb_array_elements(result) with ordinality as r(i,ord)),'[]'),
    'categories',categories,
    'shop',shop,
    'shops',featured_shops,
    'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',last_value->>'id','after_value',last_value->'sort_value') end
  ) || case when shop_meta is not null then jsonb_build_object('shop_meta',shop_meta) else '{}'::jsonb end;
end $$;

revoke all on function public.delivery_market_browse(jsonb) from public, anon;
grant execute on function public.delivery_market_browse(jsonb) to authenticated;

-- Operator RPC to seed, inspect, pause/resume, toggle auto-dispatch, or purge Virtual Showcase Stores
create or replace function public.delivery_showcase_catalog(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  v_owner uuid;
  v_paused boolean;
  v_auto boolean;
  s_rec record;
  p_rec record;
  v_rec record;
  v_shop_id uuid;
  v_prod_id uuid;
  v_var_id uuid;
  v_deleted_shops integer := 0;
  v_archived_shops integer := 0;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if not op then
    raise sqlstate 'PT403' using message = 'Chỉ điều hành viên hệ thống được quản lý dữ liệu cửa hàng ảo.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 4000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu quản lý gian hàng ảo không hợp lệ.';
  end if;

  if p_action = 'seed' then
    -- Ensure an active owner account exists for showcase shops
    insert into public.delivery_cloud_accounts(user_id, role, full_name, phone, blocked)
      values (uid, 'customer', 'GHST Showcase Culinary Hub', '0900000247', false)
      on conflict (user_id) do nothing;

    select user_id into v_owner
      from public.delivery_cloud_accounts
      where user_id = uid and not blocked;
    if v_owner is null then
      select user_id into v_owner
        from public.delivery_cloud_accounts
        where not blocked
        order by updated_at desc
        limit 1;
    end if;
    if v_owner is null then
      raise sqlstate 'PT409' using message = 'Cần ít nhất một tài khoản đang hoạt động để gắn gian hàng ảo.';
    end if;

    -- Upsert 6 Virtual Restaurants, Beverage Bars & Convenience Stores
    for s_rec in
      select * from (values
        (
          'pho-thin-com-tam',
          'Phở Thìn & Cơm Tấm Sài Gòn Xưa',
          'Quán ăn truyền thống nấu nước dùng xương ống 12 giờ, cơm tấm sườn nướng than hoa thơm lừng chuẩn vị Sài Gòn.',
          '118 Pasteur, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh',
          10.7769::float8, 106.7009::float8,
          'Cơm • Phở • Bún',
          'https://images.unsplash.com/photo-1582878826629-29b7ad1cdc43?auto=format&fit=crop&w=1200&q=80'
        ),
        (
          'gong-tea-coffee-bar',
          'The Gong & Highlands Tea Bar',
          'Trà sữa trân châu đường đen kem cheese, trà trái cây nhiệt đới giã tay và cà phê phin rang mộc đậm vị.',
          '68 Nguyễn Huệ, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh',
          10.7744::float8, 106.7035::float8,
          'Trà Sữa & Cà Phê',
          'https://images.unsplash.com/photo-1558857563-b371033873b8?auto=format&fit=crop&w=1200&q=80'
        ),
        (
          'banh-mi-an-vat-pho',
          'Bánh Mì Huỳnh Hoa & Ăn Vặt Phố',
          'Bánh mì đặc biệt full chả pate bơ tươi, gỏi cuốn tôm thịt, mẹt xiên que chiên nước mắm và bánh ngọt nướng mới mỗi giờ.',
          '26 Lê Thị Riêng, Phường Bến Thành, Quận 1, TP. Hồ Chí Minh',
          10.7712::float8, 106.6915::float8,
          'Bánh Mì & Ăn Vặt',
          'https://images.unsplash.com/photo-1509722747041-616f39b57569?auto=format&fit=crop&w=1200&q=80'
        ),
        (
          'k-chicken-burger-studio',
          'K-Chicken & Smash Burger Studio',
          'Gà rán giòn sốt cay Hàn Quốc Yangnyeom, Smash Burger bò Mỹ phô mai tan chảy và Pizza đế tươi nướng củi.',
          '145 Nguyễn Thị Minh Khai, Quận 3, TP. Hồ Chí Minh',
          10.7758::float8, 106.6904::float8,
          'Gà Rán & Đồ Âu',
          'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80'
        ),
        (
          'ep-tuoi-detox-bar',
          'Ép Tươi Cold-Pressed & Sinh Tố Nhiệt Đới',
          'Nước ép lạnh 100% nguyên chất không đường, sinh tố bơ sáp Đắk Lắk dừa non, sữa chua Hy Lạp và salad eat-clean.',
          '88 Thảo Điền, TP. Thủ Đức, TP. Hồ Chí Minh',
          10.8032::float8, 106.7336::float8,
          'Nước Ép & Healthy',
          'https://images.unsplash.com/photo-1610970881699-44a5587cabec?auto=format&fit=crop&w=1200&q=80'
        ),
        (
          'ghst-mart-247',
          'GHST Mart 24/7 — Tiện Lợi & Bách Hóa Nhanh',
          'Siêu thị tiện lợi mở cửa 24/7: nước khoáng, combo cứu đói đêm khuya, trái cây cắt sẵn, đồ uống ướp lạnh giao siêu tốc.',
          '215 Điện Biên Phủ, Quận Bình Thạnh, TP. Hồ Chí Minh',
          10.8016::float8, 106.7114::float8,
          'Cửa Hàng Tiện Lợi',
          'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1200&q=80'
        )
      ) as t(slug, name, descr, addr, lat, lng, cat_grp, banner)
    loop
      v_shop_id := md5('ghst-showcase-shop:' || s_rec.slug)::uuid;
      insert into public.delivery_market_shops(
        id, owner_id, name, description, address, latitude, longitude,
        status, paused, opening_schedule, banner_url, service_radius_km,
        is_showcase, showcase_slug, category_group, showcase_auto_dispatch
      ) values (
        v_shop_id, v_owner, s_rec.name, s_rec.descr, s_rec.addr, s_rec.lat, s_rec.lng,
        'active', false, '[]'::jsonb, s_rec.banner, 0,
        true, s_rec.slug, s_rec.cat_grp, true
      )
      on conflict (showcase_slug) do update set
        name = excluded.name,
        description = excluded.description,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        status = 'active',
        paused = false,
        opening_schedule = '[]'::jsonb,
        banner_url = excluded.banner_url,
        service_radius_km = 0,
        is_showcase = true,
        category_group = excluded.category_group,
        version = public.delivery_market_shops.version + 1,
        updated_at = now();
    end loop;

    -- Upsert 25 signature dishes, drinks & convenience products
    for p_rec in
      select * from (values
        -- Shop 1: Phở Thìn & Cơm Tấm
        (
          'pho-thin-com-tam', 'PHO-TAI-LAN-01',
          'Phở Bò Tái Lăn Nước Trong Hà Nội',
          'Thịt thăn bò tươi xào lăn tỏi thơm áp chảo lửa lớn, bánh phở mềm dai, nước dùng ninh xương ống bò trong ngọt thanh.',
          'Cơm & Món Nước', 65000, 80, 0.85::numeric, 12,
          'https://images.unsplash.com/photo-1582878826629-29b7ad1cdc43?auto=format&fit=crop&w=800&q=80',
          '[{"id":"mon_kem","name":"Món ăn kèm","min":0,"max":3,"options":[{"id":"quay_gion","name":"Quẩy giòn nóng (3 chiếc)","price":8000},{"id":"trung_chan","name":"Trứng gà ta chần","price":10000},{"id":"nuoc_beo","name":"Chén nước béo gầu bò","price":5000}]}]'::jsonb
        ),
        (
          'pho-thin-com-tam', 'COM-TAM-SUON-02',
          'Cơm Tấm Sườn Nướng Than Hoa Bì Chả',
          'Sườn cốt lết ướp mật ong nướng than hồng mềm mọng, ăn kèm bì thính, chả trứng hấp, mỡ hành tóp mỡ giòn và đồ chua.',
          'Cơm & Món Nước', 58000, 90, 0.75::numeric, 15,
          'https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=800&q=80',
          '[{"id":"them_mon","name":"Gọi thêm topping","min":0,"max":3,"options":[{"id":"op_la","name":"Trứng ốp la lòng đào","price":10000},{"id":"cha_trung","name":"Miếng chả trứng hấp thêm","price":15000},{"id":"canh_kho_qua","name":"Canh khổ qua dồn thịt","price":18000}]}]'::jsonb
        ),
        (
          'pho-thin-com-tam', 'BUN-BO-HUE-03',
          'Bún Bò Huế Giò Heo Chả Cua',
          'Nước lèo sả ruốc Huế thơm dịu, bắp bò hoa thái mỏng, khoanh giò heo rút xương giòn sần sật và viên chả cua tươi.',
          'Cơm & Món Nước', 62000, 75, 0.90::numeric, 12,
          'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=800&q=80',
          '[{"id":"do_cay","name":"Mức độ cay","min":0,"max":1,"options":[{"id":"khong_cay","name":"Không cay","price":0},{"id":"cay_vua","name":"Cay vừa chuẩn Huế","price":0},{"id":"sa_te_nong","name":"Sa tế ớt chưng cay nồng","price":3000}]},{"id":"them_topping","name":"Món thêm","min":0,"max":2,"options":[{"id":"cha_cua","name":"Thêm 2 viên chả cua","price":15000},{"id":"tiet_mem","name":"Chén tiết mềm","price":8000}]}]'::jsonb
        ),
        (
          'pho-thin-com-tam', 'MIEN-GA-TA-04',
          'Miến Gà Ta Xé Phay Măng Khô Tây Bắc',
          'Gà ta thả vườn da giòn thịt chắc xé phay, măng khô ninh mềm, miến dong dai trong không trương nở khi giao xa.',
          'Cơm & Món Nước', 55000, 65, 0.80::numeric, 10,
          'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=800&q=80',
          '[{"id":"them_ga","name":"Gọi thêm","min":0,"max":2,"options":[{"id":"trung_non","name":"Chén trứng non lòng đào","price":20000},{"id":"dui_ga","name":"Đổi sang đùi gà góc tư","price":15000}]}]'::jsonb
        ),

        -- Shop 2: The Gong & Highlands Tea Bar
        (
          'gong-tea-coffee-bar', 'TS-TRAN-CHAU-01',
          'Trà Sữa Trân Châu Đường Đen Kem Cheese',
          'Hồng trà Assam ủ lạnh phối sữa tươi thanh trùng, trân châu nấu đường đen Okinawa ấm dẻo và lớp kem phô mai mặn béo.',
          'Trà Sữa & Cà Phê', 49000, 120, 0.55::numeric, 8,
          'https://images.unsplash.com/photo-1558857563-b371033873b8?auto=format&fit=crop&w=800&q=80',
          '[{"id":"muc_duong","name":"Mức đường","min":0,"max":1,"options":[{"id":"d100","name":"100% đường chuẩn quán","price":0},{"id":"d70","name":"70% đường vừa uống","price":0},{"id":"d50","name":"50% ít ngọt","price":0},{"id":"d30","name":"30% đường thanh nhẹ","price":0}]},{"id":"muc_da","name":"Mức đá","min":0,"max":1,"options":[{"id":"da_chung","name":"100% đá tiêu chuẩn","price":0},{"id":"it_da","name":"50% đá","price":0},{"id":"da_rieng","name":"Để đá riêng giữ vị","price":0}]},{"id":"topping_ts","name":"Topping thêm","min":0,"max":3,"options":[{"id":"tc_den","name":"Thêm trân châu đường đen","price":10000},{"id":"kem_cheese","name":"Thêm lớp Kem Cheese mặn","price":15000},{"id":"pudding_trung","name":"Pudding trứng mềm mịn","price":12000},{"id":"suong_sao","name":"Thạch sương sáo thảo mộc","price":8000}]}]'::jsonb
        ),
        (
          'gong-tea-coffee-bar', 'TRA-DAO-CAM-SA-02',
          'Trà Đào Cam Sả Nhiệt Đới',
          'Trà đen ủ hương sả tươi, cam vàng cắt lát và miếng đào ngâm giòn ngọt giải nhiệt tức thì.',
          'Trà Sữa & Cà Phê', 45000, 110, 0.55::numeric, 7,
          'https://images.unsplash.com/photo-1556679343-c7306c1976bc?auto=format&fit=crop&w=800&q=80',
          '[{"id":"topping_tradao","name":"Topping trái cây","min":0,"max":3,"options":[{"id":"dao_mieng","name":"Thêm 3 miếng đào giòn","price":12000},{"id":"tc_trang","name":"Trân châu trắng giòn","price":10000},{"id":"hat_chia","name":"Hạt chia hữu cơ","price":6000}]}]'::jsonb
        ),
        (
          'gong-tea-coffee-bar', 'CAFE-SUA-DA-03',
          'Cà Phê Phin Sữa Đá Đậm Vị Sài Gòn',
          'Hạt Robusta Đắk Lắk phối Arabica Cầu Đất rang vừa, chiết xuất phin truyền thống quyện sữa đặc béo thơm.',
          'Trà Sữa & Cà Phê', 35000, 150, 0.45::numeric, 5,
          'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?auto=format&fit=crop&w=800&q=80',
          '[{"id":"gu_cafe","name":"Gu thưởng thức","min":0,"max":1,"options":[{"id":"chuan_sg","name":"Chuẩn Sài Gòn cân bằng","price":0},{"id":"bac_xiu","name":"Bạc xỉu nhiều sữa thơm béo","price":0},{"id":"dam_cafe","name":"Đậm cà phê tỉnh táo","price":5000}]}]'::jsonb
        ),
        (
          'gong-tea-coffee-bar', 'MATCHA-LATTE-04',
          'Matcha Uji Latte Kem Muối Biển',
          'Bột trà xanh Uji Nhật Bản đánh tay mịn mượt trên nền sữa tươi lạnh, phủ kem muối biển mặn nhẹ cuốn hút.',
          'Trà Sữa & Cà Phê', 55000, 85, 0.55::numeric, 8,
          'https://images.unsplash.com/photo-1515823662972-da6a2e4d3002?auto=format&fit=crop&w=800&q=80',
          '[{"id":"sua_hat","name":"Tùy chọn nền sữa","min":0,"max":1,"options":[{"id":"sua_tuoi","name":"Sữa tươi thanh trùng","price":0},{"id":"sua_yen_mach","name":"Đổi sữa yến mạch Oatside","price":12000}]}]'::jsonb
        ),
        (
          'gong-tea-coffee-bar', 'TRA-MANG-CAU-05',
          'Trà Ô Long Mãng Cầu Tươi Giã Tay',
          'Thịt mãng cầu xiêm chín cây giã tay chua ngọt tự nhiên kết hợp nền lục trà ô long thanh mát.',
          'Trà Sữa & Cà Phê', 52000, 90, 0.60::numeric, 8,
          'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=80',
          '[{"id":"topping_mc","name":"Topping giòn","min":0,"max":2,"options":[{"id":"tc_trang_mc","name":"Trân châu trắng 3Q","price":10000},{"id":"thach_dua","name":"Thạch dừa sợi Bến Tre","price":8000}]}]'::jsonb
        ),

        -- Shop 3: Bánh Mì Huỳnh Hoa & Ăn Vặt Phố
        (
          'banh-mi-an-vat-pho', 'BANH-MI-FULL-01',
          'Bánh Mì Đặc Biệt Full Chả Pate Bơ Tươi',
          'Ổ bánh mì nóng giòn đầy ắp 6 loại thịt nguội, chả lụa, chả bò, dăm bông, pate gan bùi béo, bơ trứng gà tươi và chà bông.',
          'Ăn Vặt & Bánh Ngọt', 48000, 100, 0.45::numeric, 6,
          'https://images.unsplash.com/photo-1509722747041-616f39b57569?auto=format&fit=crop&w=800&q=80',
          '[{"id":"rau_ot","name":"Tùy chọn rau & ớt","min":0,"max":2,"options":[{"id":"day_du","name":"Đầy đủ hành ngò dưa đồ chua","price":0},{"id":"khong_ot","name":"Không bỏ ớt","price":0},{"id":"rau_rieng","name":"Để riêng túi rau & đồ chua","price":2000},{"id":"them_pate","name":"Thêm phần pate gan đặc biệt","price":10000}]}]'::jsonb
        ),
        (
          'banh-mi-an-vat-pho', 'GOI-CUON-TOM-02',
          'Gỏi Cuốn Tôm Thịt Sốt Tương Đậu Phộng (4 Cuốn)',
          'Tôm sú tươi luộc đỏ au, thịt ba rọi mềm, bún tươi và rau sống cuốn chặt tay kèm sốt tương đen đậu phộng rang giòn.',
          'Ăn Vặt & Bánh Ngọt', 44000, 85, 0.50::numeric, 8,
          'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=800&q=80',
          '[{"id":"nuoc_cham","name":"Loại nước chấm","min":0,"max":2,"options":[{"id":"tuong_den","name":"Tương đen đậu phộng bùi béo","price":0},{"id":"mam_nem","name":"Mắm nêm dứa thơm nồng","price":0}]}]'::jsonb
        ),
        (
          'banh-mi-an-vat-pho', 'MET-XIEN-QUE-03',
          'Mẹt Xiên Que & Cá Viên Chiên Nước Mắm Tỏi Ớt',
          'Cá viên, bò viên, tôm surimi, hoành thánh phô mai đảo sốt nước mắm đường tỏi phi thơm nức mũi kèm đậu bắp.',
          'Ăn Vặt & Bánh Ngọt', 59000, 75, 0.65::numeric, 12,
          'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=800&q=80',
          '[{"id":"them_xien","name":"Gọi thêm xiên","min":0,"max":2,"options":[{"id":"rau_muong","name":"Thêm rau muống & đậu bắp xào bơ","price":12000},{"id":"xx_phomai","name":"Thêm 2 xúc xích phô mai chảy","price":18000}]}]'::jsonb
        ),
        (
          'banh-mi-an-vat-pho', 'CROISSANT-TRUNG-MUOI-04',
          'Bánh Sừng Bò Croissant Sốt Trứng Muối Tan Chảy',
          'Vỏ bánh ngàn lớp bơ Pháp nướng vàng giòn rụm, bên trong tràn đầy nhân kim sa trứng muối béo mặn thơm lừng.',
          'Ăn Vặt & Bánh Ngọt', 42000, 60, 0.30::numeric, 6,
          'https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=800&q=80',
          '[]'::jsonb
        ),

        -- Shop 4: K-Chicken & Smash Burger Studio
        (
          'k-chicken-burger-studio', 'GA-RAN-HQ-01',
          'Combo Gà Rán Giòn Sốt Cay Hàn Quốc + Khoai Lắc',
          'Gà tươi tẩm bột chiên kép giòn tan phủ sốt Yangnyeom cay ngọt chuẩn Seoul, kèm khoai tây lắc phô mai và củ cải muối.',
          'Thức Ăn Nhanh', 89000, 80, 0.85::numeric, 16,
          'https://images.unsplash.com/photo-1626645738196-c2a7c87a8f58?auto=format&fit=crop&w=800&q=80',
          '[{"id":"vi_sot","name":"Chọn vị sốt phủ gà","min":0,"max":1,"options":[{"id":"sot_cay","name":"Sốt Cay Hàn Quốc Yangnyeom","price":0},{"id":"bo_toi","name":"Sốt Bơ Tỏi Mật Ong","price":0},{"id":"pho_mai_tuyet","name":"Phủ Bột Phô Mai Tuyết","price":8000}]}]'::jsonb
        ),
        (
          'k-chicken-burger-studio', 'SMASH-BURGER-02',
          'Double Smash Burger Bò Mỹ Phô Mai Cheddar',
          'Hai lớp thịt bò Mỹ nướng áp chảo xém cạnh thơm lừng, phô mai Cheddar tan chảy, hành tây caramel và sốt Burger bí truyền.',
          'Thức Ăn Nhanh', 79000, 70, 0.55::numeric, 14,
          'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=80',
          '[{"id":"burger_addon","name":"Nâng cấp nhân Burger","min":0,"max":3,"options":[{"id":"bacon","name":"Thịt xông khói nướng giòn","price":18000},{"id":"extra_cheese","name":"Thêm lát phô mai Cheddar","price":12000},{"id":"fries_side","name":"Kèm phần khoai tây chiên giòn","price":22000}]}]'::jsonb
        ),
        (
          'k-chicken-burger-studio', 'PIZZA-HAI-SAN-03',
          'Pizza Hải Sản Sốt Pesto Đế Tươi',
          'Tôm tươi, mực ống, thanh cua trên nền sốt húng quế Pesto thơm mát và phô mai Mozzarella kéo sợi.',
          'Thức Ăn Nhanh', 129000, 50, 0.95::numeric, 18,
          'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=80',
          '[]'::jsonb
        ),
        (
          'k-chicken-burger-studio', 'MI-Y-BO-BAM-04',
          'Mì Ý Bò Bằm Đút Lò Phô Mai Mozzarella',
          'Sốt cà chua thịt bò bằm hầm chậm kiểu Ý, phủ đầy phô mai Mozzarella đút lò vàng ươm.',
          'Thức Ăn Nhanh', 69000, 65, 0.65::numeric, 15,
          'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?auto=format&fit=crop&w=800&q=80',
          '[]'::jsonb
        ),

        -- Shop 5: Ép Tươi Cold-Pressed & Sinh Tố Nhiệt Đới
        (
          'ep-tuoi-detox-bar', 'NUOC-EP-CAM-CAROT-01',
          'Nước Ép Lạnh Cam Vàng Cà Rốt Gừng Tươi',
          'Ép chậm thủy lực giữ trọn vitamin C & beta-carotene từ cam vàng Úc, cà rốt Đà Lạt và lát gừng ấm bụng.',
          'Đồ Uống Healthy', 48000, 90, 0.50::numeric, 6,
          'https://images.unsplash.com/photo-1610970881699-44a5587cabec?auto=format&fit=crop&w=800&q=80',
          '[{"id":"vi_ngot","name":"Độ ngọt tự nhiên","min":0,"max":1,"options":[{"id":"nguyen_chat","name":"Nguyên chất 100% không đường","price":0},{"id":"mat_ong","name":"Pha chút mật ong hoa nhãn","price":6000}]}]'::jsonb
        ),
        (
          'ep-tuoi-detox-bar', 'SINH-TO-BO-DUA-02',
          'Sinh Tố Bơ Sáp Đắk Lắk Dừa Non Đảo Giòn',
          'Bơ sáp dẻo quánh xay mịn cùng nước cốt dừa tươi, rắc dừa sấy giòn và cơm dừa non mềm ngọt.',
          'Đồ Uống Healthy', 54000, 75, 0.55::numeric, 7,
          'https://images.unsplash.com/photo-1623065422902-30a2d299bbe4?auto=format&fit=crop&w=800&q=80',
          '[{"id":"topping_st","name":"Topping dinh dưỡng","min":0,"max":2,"options":[{"id":"com_dua","name":"Thêm cơm dừa non dẻo","price":12000},{"id":"hanh_nhan","name":"Hạnh nhân lát nướng bơ","price":10000}]}]'::jsonb
        ),
        (
          'ep-tuoi-detox-bar', 'SUA-CHUA-HY-LAP-03',
          'Tô Sữa Chua Hy Lạp Granola & Trái Cây Mùa Hè',
          'Sữa chua Hy Lạp đặc sánh giàu đạm ăn cùng dâu tây, xoài cát, việt quất và hạt ngũ cốc Granola nướng mật ong.',
          'Đồ Uống Healthy', 65000, 60, 0.50::numeric, 8,
          'https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=800&q=80',
          '[{"id":"them_hat","name":"Thêm sốt hạt","min":0,"max":1,"options":[{"id":"bo_dau_phong","name":"Sốt bơ đậu phộng nguyên chất","price":10000}]}]'::jsonb
        ),
        (
          'ep-tuoi-detox-bar', 'SALAD-UC-GA-04',
          'Salad Ức Gà Áp Chảo Sốt Mè Rang Nhật Bản',
          'Ức gà phi lê ướp thảo mộc áp chảo mềm mọng, xà lách thủy canh, cà chua bi, bắp ngọt và sốt mè rang Kewpie.',
          'Đồ Uống Healthy', 68000, 55, 0.60::numeric, 10,
          'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=800&q=80',
          '[{"id":"them_protein","name":"Bổ sung dinh dưỡng","min":0,"max":2,"options":[{"id":"bo_sap","name":"Thêm nửa trái bơ sáp tươi","price":18000},{"id":"trung_luoc","name":"Thêm trứng gà lòng đào","price":10000}]}]'::jsonb
        ),

        -- Shop 6: GHST Mart 24/7
        (
          'ghst-mart-247', 'MART-LAVIE-01',
          'Lốc 6 Chai Nước Khoáng Thiên Nhiên LaVie 500ml',
          'Nước khoáng thiên nhiên dịu nhẹ đóng chai tiện lợi cho văn phòng, gia đình và dã ngoại.',
          'Bách Hóa & Tiện Lợi', 36000, 120, 3.10::numeric, 3,
          'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=800&q=80',
          '[]'::jsonb
        ),
        (
          'ghst-mart-247', 'MART-COMBO-DEM-02',
          'Combo Cứu Đói Đêm Khuya (2 Mì Ly + Xúc Xích + Trà Ô Long)',
          'Gói tiện lợi gồm 2 mì ly lẩu thái tôm chua cay, 2 cây xúc xích tiệt trùng và 1 chai trà Ô Long giải ngấy.',
          'Bách Hóa & Tiện Lợi', 49000, 95, 0.90::numeric, 4,
          'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=800&q=80',
          '[{"id":"tien_ich","name":"Tiện ích đi kèm","min":0,"max":2,"options":[{"id":"dua_muong","name":"Kèm bộ muỗng đũa & khăn giấy","price":0},{"id":"trung_an_lien","name":"Thêm 2 quả trứng gà ăn liền","price":16000}]}]'::jsonb
        ),
        (
          'ghst-mart-247', 'MART-TRAI-CAY-03',
          'Hộp Trái Cây Cắt Sẵn 4 Mùa Kèm Muối Ô Mai (500g)',
          'Ổi nữ hoàng, xoài keo, mận An Phước và dứa mật gọt sẵn ướp mát, tặng kèm hũ muối tôm ô mai chua ngọt.',
          'Bách Hóa & Tiện Lợi', 52000, 70, 0.55::numeric, 5,
          'https://images.unsplash.com/photo-1619566636858-adf3ef46400b?auto=format&fit=crop&w=800&q=80',
          '[]'::jsonb
        ),
        (
          'ghst-mart-247', 'MART-NUOC-NGOT-04',
          'Lốc 4 Lon Nước Giải Khát Có Ga & Tăng Lực Ướp Lạnh',
          'Giao kèm túi giữ nhiệt lạnh sâu, sảng khoái tức thì cho buổi tiệc hoặc ca làm việc chiều.',
          'Bách Hóa & Tiện Lợi', 56000, 110, 1.45::numeric, 3,
          'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=800&q=80',
          '[{"id":"giu_lanh","name":"Đóng gói lạnh","min":0,"max":1,"options":[{"id":"tui_da","name":"Thêm túi đá gel giữ lạnh 2 giờ","price":5000}]}]'::jsonb
        )
      ) as t(shop_slug, sku, name, descr, cat, price, stock, wt, prep, img, opts)
    loop
      v_shop_id := md5('ghst-showcase-shop:' || p_rec.shop_slug)::uuid;
      v_prod_id := md5('ghst-showcase-prod:' || p_rec.sku)::uuid;
      insert into public.delivery_market_products(
        id, shop_id, name, description, category, sku, image_url,
        price, stock, weight_kg, published, option_groups, sale_schedule,
        preparation_minutes, images
      ) values (
        v_prod_id, v_shop_id, p_rec.name, p_rec.descr, p_rec.cat, p_rec.sku, p_rec.img,
        p_rec.price, p_rec.stock, p_rec.wt, true, p_rec.opts, '[]'::jsonb,
        p_rec.prep, jsonb_build_array(p_rec.img)
      )
      on conflict on constraint delivery_market_products_pkey do update set
        name = excluded.name,
        description = excluded.description,
        category = excluded.category,
        sku = excluded.sku,
        image_url = excluded.image_url,
        price = excluded.price,
        stock = greatest(public.delivery_market_products.stock, excluded.stock),
        weight_kg = excluded.weight_kg,
        published = true,
        option_groups = excluded.option_groups,
        sale_schedule = '[]'::jsonb,
        preparation_minutes = excluded.preparation_minutes,
        images = excluded.images,
        version = public.delivery_market_products.version + 1,
        updated_at = now();
    end loop;

    -- Upsert SKU Variants (Sizes / Portions)
    for v_rec in
      select * from (values
        ('PHO-TAI-LAN-01', 'PHO-TAI-LAN-STD', 'Tô Tiêu Chuẩn', 65000, 60, 0.85::numeric),
        ('PHO-TAI-LAN-01', 'PHO-TAI-LAN-DB', 'Tô Đặc Biệt (Thêm Gầu & Gân)', 85000, 45, 1.05::numeric),
        ('COM-TAM-SUON-02', 'COM-TAM-SUON', 'Dĩa Cơm Sườn Nướng', 58000, 60, 0.75::numeric),
        ('COM-TAM-SUON-02', 'COM-TAM-FULL', 'Dĩa Đặc Biệt Sườn Bì Chả Trứng', 75000, 50, 0.95::numeric),
        ('TS-TRAN-CHAU-01', 'TS-TC-SIZE-M', 'Size M (500ml)', 49000, 80, 0.55::numeric),
        ('TS-TRAN-CHAU-01', 'TS-TC-SIZE-L', 'Size L (700ml)', 59000, 70, 0.75::numeric),
        ('TRA-DAO-CAM-SA-02', 'TDCS-SIZE-M', 'Size M (500ml)', 45000, 80, 0.55::numeric),
        ('TRA-DAO-CAM-SA-02', 'TDCS-SIZE-L', 'Size L (700ml)', 55000, 70, 0.75::numeric),
        ('CAFE-SUA-DA-03', 'CFSD-STD', 'Ly Vừa Tỉnh Táo', 35000, 90, 0.45::numeric),
        ('CAFE-SUA-DA-03', 'CFSD-LARGE', 'Ly Lớn Gấp Đôi Phin', 45000, 80, 0.60::numeric),
        ('MATCHA-LATTE-04', 'MATCHA-M', 'Size M (500ml)', 55000, 50, 0.55::numeric),
        ('MATCHA-LATTE-04', 'MATCHA-L', 'Size L (700ml)', 65000, 50, 0.75::numeric),
        ('GA-RAN-HQ-01', 'GARAN-COMBO-1', 'Combo 1 Người (3 Miếng + Khoai)', 89000, 50, 0.85::numeric),
        ('GA-RAN-HQ-01', 'GARAN-COMBO-2', 'Combo Đôi (6 Miếng + Khoai + 2 Nước)', 169000, 40, 1.65::numeric),
        ('PIZZA-HAI-SAN-03', 'PIZZA-9IN', 'Cỡ Vừa 9 Inch (6 Miếng)', 129000, 35, 0.95::numeric),
        ('PIZZA-HAI-SAN-03', 'PIZZA-12IN', 'Cỡ Lớn 12 Inch Viền Phô Mai', 179000, 30, 1.35::numeric),
        ('MART-LAVIE-01', 'LAVIE-LOC-6', 'Lốc 6 Chai 500ml', 36000, 80, 3.10::numeric),
        ('MART-LAVIE-01', 'LAVIE-THUNG-24', 'Thùng 24 Chai 500ml', 125000, 40, 12.40::numeric)
      ) as t(prod_sku, var_sku, title, price, stock, wt)
    loop
      v_prod_id := md5('ghst-showcase-prod:' || v_rec.prod_sku)::uuid;
      v_var_id := md5('ghst-showcase-var:' || v_rec.var_sku)::uuid;
      insert into public.delivery_market_variants(
        id, product_id, sku, title, price, stock, weight_kg, published
      ) values (
        v_var_id, v_prod_id, v_rec.var_sku, v_rec.title, v_rec.price, v_rec.stock, v_rec.wt, true
      )
      on conflict (id) do update set
        sku = excluded.sku,
        title = excluded.title,
        price = excluded.price,
        stock = greatest(public.delivery_market_variants.stock, excluded.stock),
        weight_kg = excluded.weight_kg,
        published = true,
        version = public.delivery_market_variants.version + 1,
        updated_at = now();
    end loop;

    -- Upsert 2 active Showcase Vouchers
    insert into public.delivery_market_vouchers(
      id, code, shop_id, title, discount_kind, discount_value, max_discount,
      min_subtotal, budget_total, per_user_limit, starts_at, ends_at, active, created_by
    ) values
      (
        md5('ghst-showcase-voucher:ANNGON25K')::uuid,
        'ANNGON25K',
        null,
        'Giảm 25.000đ đơn Ẩm thực & Mua sắm từ 99K',
        'fixed', 25000, 25000, 99000, 50000000, 5,
        now() - interval '5 minutes', now() + interval '30 days', true, uid
      ),
      (
        md5('ghst-showcase-voucher:TRASUA15K')::uuid,
        'TRASUA15K',
        md5('ghst-showcase-shop:gong-tea-coffee-bar')::uuid,
        'Giảm 15.000đ Trà Sữa & Cà Phê đơn từ 60K',
        'fixed', 15000, 15000, 60000, 25000000, 5,
        now() - interval '5 minutes', now() + interval '30 days', true, uid
      )
    on conflict (code) do update set
      title = excluded.title,
      active = true,
      starts_at = now() - interval '5 minutes',
      ends_at = now() + interval '30 days',
      budget_total = greatest(public.delivery_market_vouchers.budget_total, excluded.budget_total),
      version = public.delivery_market_vouchers.version + 1,
      updated_at = now();

    -- Upsert 3 active Flash Sales on signature showcase items
    insert into public.delivery_market_flash_sales(
      id, product_id, shop_id, sale_price, allocated_stock, per_user_limit, starts_at, ends_at, active
    ) values
      (
        md5('ghst-showcase-fs:TS-TRAN-CHAU-01')::uuid,
        md5('ghst-showcase-prod:TS-TRAN-CHAU-01')::uuid,
        md5('ghst-showcase-shop:gong-tea-coffee-bar')::uuid,
        39000, 60, 4, now() - interval '5 minutes', now() + interval '14 days', true
      ),
      (
        md5('ghst-showcase-fs:PHO-TAI-LAN-01')::uuid,
        md5('ghst-showcase-prod:PHO-TAI-LAN-01')::uuid,
        md5('ghst-showcase-shop:pho-thin-com-tam')::uuid,
        55000, 50, 4, now() - interval '5 minutes', now() + interval '14 days', true
      ),
      (
        md5('ghst-showcase-fs:GA-RAN-HQ-01')::uuid,
        md5('ghst-showcase-prod:GA-RAN-HQ-01')::uuid,
        md5('ghst-showcase-shop:k-chicken-burger-studio')::uuid,
        75000, 40, 4, now() - interval '5 minutes', now() + interval '14 days', true
      )
    on conflict (id) do update set
      sale_price = excluded.sale_price,
      allocated_stock = greatest(public.delivery_market_flash_sales.sold_stock + 20, excluded.allocated_stock),
      starts_at = now() - interval '5 minutes',
      ends_at = now() + interval '14 days',
      active = true,
      version = public.delivery_market_flash_sales.version + 1,
      updated_at = now();

    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'showcase_catalog_seed', null, jsonb_build_object('shops', 6, 'products', 25));

    p_action := 'status';

  elsif p_action = 'set_paused' then
    if jsonb_typeof(d->'paused') is distinct from 'boolean' then
      raise sqlstate 'PT400' using message = 'Trạng thái tạm ẩn không hợp lệ.';
    end if;
    v_paused := (d->>'paused')::boolean;
    update public.delivery_market_shops
      set paused = v_paused,
          version = version + 1,
          updated_at = now()
      where is_showcase;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'showcase_catalog_set_paused', null, jsonb_build_object('paused', v_paused));
    p_action := 'status';

  elsif p_action = 'set_auto_dispatch' then
    if jsonb_typeof(d->'enabled') is distinct from 'boolean' then
      raise sqlstate 'PT400' using message = 'Cấu hình tự động điều phối không hợp lệ.';
    end if;
    v_auto := (d->>'enabled')::boolean;
    update public.delivery_market_shops
      set showcase_auto_dispatch = v_auto,
          version = version + 1,
          updated_at = now()
      where is_showcase;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'showcase_catalog_auto_dispatch', null, jsonb_build_object('enabled', v_auto));
    p_action := 'status';

  elsif p_action = 'purge' then
    -- Disable showcase global voucher if unused, or deactivate if used
    update public.delivery_market_vouchers
      set active = false, updated_at = now()
      where id in (
        md5('ghst-showcase-voucher:ANNGON25K')::uuid,
        md5('ghst-showcase-voucher:TRASUA15K')::uuid
      );
    delete from public.delivery_market_vouchers
      where id in (
        md5('ghst-showcase-voucher:ANNGON25K')::uuid,
        md5('ghst-showcase-voucher:TRASUA15K')::uuid
      )
      and not exists(select 1 from public.delivery_market_voucher_usages vu where vu.voucher_id = public.delivery_market_vouchers.id);

    for s_rec in select id from public.delivery_market_shops where is_showcase for update loop
      delete from public.delivery_market_cart_items
        where product_id in (select id from public.delivery_market_products where shop_id = s_rec.id);
      delete from public.delivery_market_favorites
        where product_id in (select id from public.delivery_market_products where shop_id = s_rec.id);
      delete from public.delivery_market_shop_follows where shop_id = s_rec.id;

      if exists(select 1 from public.delivery_market_shop_orders where shop_id = s_rec.id) then
        update public.delivery_market_flash_sales set active = false, updated_at = now() where shop_id = s_rec.id;
        update public.delivery_market_products set published = false, version = version + 1, updated_at = now() where shop_id = s_rec.id;
        update public.delivery_market_shops set paused = true, status = 'suspended', version = version + 1, updated_at = now() where id = s_rec.id;
        v_archived_shops := v_archived_shops + 1;
      else
        delete from public.delivery_market_flash_sales where shop_id = s_rec.id;
        delete from public.delivery_market_vouchers
          where shop_id = s_rec.id
            and not exists(select 1 from public.delivery_market_voucher_usages vu where vu.voucher_id = public.delivery_market_vouchers.id);
        delete from public.delivery_market_stock
          where product_id in (select id from public.delivery_market_products where shop_id = s_rec.id);
        delete from public.delivery_market_variants
          where product_id in (select id from public.delivery_market_products where shop_id = s_rec.id);
        delete from public.delivery_market_products where shop_id = s_rec.id;
        delete from public.delivery_market_shops where id = s_rec.id;
        v_deleted_shops := v_deleted_shops + 1;
      end if;
    end loop;

    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'showcase_catalog_purge', null, jsonb_build_object('deleted_shops', v_deleted_shops, 'archived_shops', v_archived_shops));
    p_action := 'status';
  end if;

  if p_action = 'status' then
    return jsonb_build_object(
      'seeded', exists(select 1 from public.delivery_market_shops where is_showcase and status = 'active'),
      'shops_total', (select count(*)::int from public.delivery_market_shops where is_showcase),
      'shops_active', (select count(*)::int from public.delivery_market_shops where is_showcase and status = 'active' and not paused),
      'shops_paused', (select count(*)::int from public.delivery_market_shops where is_showcase and (paused or status <> 'active')),
      'products_total', (
        select count(*)::int
        from public.delivery_market_products p
        join public.delivery_market_shops s on s.id = p.shop_id
        where s.is_showcase and p.published
      ),
      'variants_total', (
        select count(*)::int
        from public.delivery_market_variants v
        join public.delivery_market_products p on p.id = v.product_id
        join public.delivery_market_shops s on s.id = p.shop_id
        where s.is_showcase and v.published
      ),
      'flash_sales_active', (
        select count(*)::int
        from public.delivery_market_flash_sales fs
        join public.delivery_market_shops s on s.id = fs.shop_id
        where s.is_showcase and fs.active and fs.ends_at > now()
      ),
      'auto_dispatch', coalesce((select bool_and(showcase_auto_dispatch) from public.delivery_market_shops where is_showcase), true),
      'shops', coalesce((
        select jsonb_agg(to_jsonb(x) order by x.showcase_slug)
        from (
          select
            s.id, s.name, s.showcase_slug, s.category_group, s.address, s.status, s.paused,
            s.showcase_auto_dispatch, s.banner_url,
            (select count(*)::int from public.delivery_market_products p where p.shop_id = s.id and p.published) as product_count
          from public.delivery_market_shops s
          where s.is_showcase
          order by s.showcase_slug
        ) x
      ), '[]'::jsonb)
    );
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác quản lý gian hàng ảo không hỗ trợ.';
end; $$;

revoke all on function public.delivery_showcase_catalog(text, jsonb) from public, anon;
grant execute on function public.delivery_showcase_catalog(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
