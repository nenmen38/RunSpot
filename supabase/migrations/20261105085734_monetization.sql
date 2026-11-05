-- 운영자가 등록한 기간에만 광고와 제휴 혜택을 공개합니다.
create table runspot_private.race_promotions (
  event_id text primary key references runspot_private.marathon_catalog(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  enabled boolean not null default false,
  check (starts_at < ends_at)
);

create table runspot_private.shop_offers (
  id uuid primary key default gen_random_uuid(),
  shop_name text not null check (length(btrim(shop_name)) between 1 and 80),
  shop_address text not null check (length(btrim(shop_address)) between 1 and 180),
  terms text not null check (length(btrim(terms)) between 1 and 240),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  commission_bps integer not null check (commission_bps between 0 and 10000),
  enabled boolean not null default false,
  check (starts_at < ends_at)
);

create table runspot_private.shop_coupons (
  code uuid primary key default gen_random_uuid(),
  offer_id uuid not null references runspot_private.shop_offers(id),
  user_id uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  sale_krw integer check (sale_krw > 0),
  commission_bps integer not null check (commission_bps between 0 and 10000),
  commission_krw bigint generated always as (sale_krw::bigint * commission_bps / 10000) stored,
  unique (user_id, offer_id),
  check ((redeemed_at is null) = (sale_krw is null))
);

-- 외부 결제 시스템 식별자는 공개 프로필의 계정 식별자와 분리합니다.
create table runspot_private.cosmetic_customers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  customer_id uuid not null unique default gen_random_uuid()
);

alter table runspot_private.cosmetic_customers enable row level security;
revoke all on runspot_private.cosmetic_customers from public, anon, authenticated;
alter table runspot_private.race_promotions enable row level security;
alter table runspot_private.shop_offers enable row level security;
alter table runspot_private.shop_coupons enable row level security;
revoke all on runspot_private.race_promotions, runspot_private.shop_offers,
  runspot_private.shop_coupons from public, anon, authenticated;

create or replace function runspot_private.marathon_events()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform runspot_private.require_board_viewer();
  return jsonb_build_object(
    'synced_at',(select synced_at from runspot_private.marathon_sync_state where singleton),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'data',m.data,
      'status',runspot_private.marathon_status(m.data->'registration',m.event_date),
      'promoted_until',p.ends_at) order by m.event_date,m.id),'[]'::jsonb)
      from runspot_private.marathon_catalog m
      left join runspot_private.race_promotions p on p.event_id=m.id
        and p.enabled and now() >= p.starts_at and now() < p.ends_at
      where m.available and m.event_date >= (now() at time zone 'Asia/Seoul')::date));
end;
$$;

create function runspot_private.active_shop_offers()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'shop_name',o.shop_name,'shop_address',o.shop_address,'terms',o.terms,
    'ends_at',o.ends_at,'code',case when c.redeemed_at is null then c.code end,
    'redeemed',c.redeemed_at is not null) order by o.ends_at,o.id),'[]'::jsonb)
    from runspot_private.shop_offers o
    left join runspot_private.shop_coupons c on c.offer_id=o.id and c.user_id=viewer
    where o.enabled and now() >= o.starts_at and now() < o.ends_at);
end;
$$;

create function runspot_private.claim_shop_coupon(offer uuid)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer(); rate integer;
begin
  select commission_bps into rate from runspot_private.shop_offers
    where id=offer and enabled and now() >= starts_at and now() < ends_at for share;
  if not found then raise exception '사용 가능한 혜택이 아닙니다.'; end if;
  insert into runspot_private.shop_coupons(offer_id,user_id,commission_bps)
    values(offer,viewer,rate) on conflict(user_id,offer_id) do nothing;
end;
$$;

-- 매장 구매 확인 후 운영자가 한 번만 사용 처리합니다.
create function runspot_private.redeem_shop_coupon(coupon uuid, amount_krw integer)
returns bigint language plpgsql security invoker set search_path='' as $$
declare fee bigint;
begin
  if amount_krw is null or amount_krw <= 0 then raise exception '결제 금액이 올바르지 않습니다.'; end if;
  update runspot_private.shop_coupons c set redeemed_at=now(),sale_krw=amount_krw
    from runspot_private.shop_offers o where o.id=c.offer_id and c.code=coupon
    and c.user_id is not null and c.redeemed_at is null and o.enabled and now() >= o.starts_at and now() < o.ends_at
    returning c.commission_krw into fee;
  if not found then raise exception '사용할 수 없는 쿠폰입니다.'; end if;
  return fee;
end;
$$;

create function runspot_private.cosmetic_customer()
returns uuid language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer(); customer uuid;
begin
  select customer_id into customer from runspot_private.cosmetic_customers where user_id=viewer;
  if found then return customer; end if;
  insert into runspot_private.cosmetic_customers(user_id) values(viewer)
    on conflict(user_id) do nothing;
  return (select customer_id from runspot_private.cosmetic_customers where user_id=viewer);
end;
$$;

create function public.cosmetic_customer()
returns uuid language sql security invoker set search_path='' as $$
  select runspot_private.cosmetic_customer();
$$;

create function public.active_shop_offers()
returns jsonb language sql stable security invoker set search_path='' as $$
  select runspot_private.active_shop_offers();
$$;
create function public.claim_shop_coupon(offer uuid)
returns void language sql security invoker set search_path='' as $$
  select runspot_private.claim_shop_coupon(offer);
$$;

revoke all on function runspot_private.active_shop_offers(),runspot_private.claim_shop_coupon(uuid),
  runspot_private.redeem_shop_coupon(uuid,integer),public.active_shop_offers(),public.claim_shop_coupon(uuid)
  from public,anon,authenticated,service_role;
grant execute on function runspot_private.active_shop_offers(),runspot_private.claim_shop_coupon(uuid),
  public.active_shop_offers(),public.claim_shop_coupon(uuid) to authenticated;
revoke all on function runspot_private.cosmetic_customer(), public.cosmetic_customer()
  from public, anon, authenticated, service_role;
grant execute on function runspot_private.cosmetic_customer(), public.cosmetic_customer()
  to authenticated;
notify pgrst,'reload schema';
