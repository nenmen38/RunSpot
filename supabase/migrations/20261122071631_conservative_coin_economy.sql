-- 운영과 격리된 결제 테스트 DB는 각자 한 환경의 거래만 장부에 반영합니다.
create table runspot_private.coin_economy_settings (
  singleton boolean primary key default true check (singleton),
  store_environment text not null default 'PRODUCTION'
    check (store_environment in ('PRODUCTION', 'SANDBOX')),
  quests_start_at timestamptz not null default now()
);
insert into runspot_private.coin_economy_settings default values;
alter table runspot_private.coin_economy_settings enable row level security;
revoke all on runspot_private.coin_economy_settings from public, anon, authenticated;

-- 구매 알림보다 먼저 온 환불도 거래별로 남깁니다.
create table runspot_private.coin_refunds (
  transaction_id text not null check (length(transaction_id) between 1 and 200),
  environment text not null check (environment in ('PRODUCTION', 'SANDBOX')),
  refunded_at timestamptz not null default now(),
  primary key (environment, transaction_id)
);
alter table runspot_private.coin_refunds enable row level security;
revoke all on runspot_private.coin_refunds from public, anon, authenticated;

create table runspot_private.weekly_coin_rewards (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  coins integer not null check (coins = 20),
  awarded_at timestamptz not null default now(),
  primary key (user_id, week_start)
);
alter table runspot_private.weekly_coin_rewards enable row level security;
revoke all on runspot_private.weekly_coin_rewards from public, anon, authenticated;

create index runs_weekly_coin_eligible_idx on public.runs(user_id, started_at)
  where distance_m >= 1000 and not review_pending and integrity_status <> 'rejected';

create function runspot_private.weekly_coin_days(target uuid, week_start date)
returns integer language sql stable security definer set search_path = '' as $$
  select count(distinct (r.started_at at time zone 'Asia/Seoul')::date)::integer
  from public.runs r join runspot_private.run_rewards w on w.run_id = r.id
  where r.user_id = target and r.distance_m >= 1000 and w.xp > 0
    and not r.review_pending and r.integrity_status <> 'rejected'
    and (r.motion_evidence is not null or r.integrity_status = 'verified')
    and r.started_at >= greatest(
      week_start::timestamp at time zone 'Asia/Seoul',
      (select quests_start_at from runspot_private.coin_economy_settings)
    )
    and r.started_at < (week_start + 7)::timestamp at time zone 'Asia/Seoul'
    and r.ended_at <= now();
$$;

create function runspot_private.award_weekly_coins()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  started timestamptz;
  reward_week date;
begin
  select r.started_at into started from public.runs r
  where r.id = new.run_id and r.distance_m >= 1000
    and (r.motion_evidence is not null or r.integrity_status = 'verified');
  if started is null then return null; end if;
  reward_week := date_trunc('week', started at time zone 'Asia/Seoul')::date;
  if not exists (
    select 1 from runspot_private.weekly_coin_rewards
    where user_id = new.user_id and week_start = reward_week
  ) and runspot_private.weekly_coin_days(new.user_id, reward_week) >= 2 then
    insert into runspot_private.weekly_coin_rewards(user_id, week_start, coins)
    values (new.user_id, reward_week, 20) on conflict do nothing;
  end if;
  return null;
end;
$$;
revoke all on function runspot_private.weekly_coin_days(uuid,date),
  runspot_private.award_weekly_coins() from public, anon, authenticated;
create trigger run_rewards_weekly_coins after insert or update of xp
  on runspot_private.run_rewards for each row when (new.xp > 0)
  execute function runspot_private.award_weekly_coins();

create or replace function runspot_private.frame_price(frame text)
returns integer language sql immutable set search_path = '' as $$
  select case frame when 'basic' then 200 when 'aura' then 700 end;
$$;

create or replace function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path = '' as $$
  select case item
    when 'route_neon' then 150 when 'route_gold' then 300 when 'route_rainbow' then 500
    when 'title_gold' then 150 when 'title_neon' then 200 when 'title_gradient' then 250
    when 'title_crown' then 150 when 'title_fire' then 150
    when 'bubble_mint' then 100 when 'bubble_sunset' then 200 when 'bubble_night' then 150 when 'bubble_pink' then 150
  end;
$$;

create or replace function runspot_private.crew_expansion_price()
returns integer language sql immutable set search_path = '' as $$ select 600; $$;
create or replace function runspot_private.crew_ticket_price()
returns integer language sql immutable set search_path = '' as $$ select 300; $$;

create function runspot_private.crew_ticket_price_for(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select case when exists (
    select 1 from runspot_private.crew_tickets where user_id = target
  ) or exists (
    select 1 from runspot_private.crews where owner_id = target
  ) then runspot_private.crew_ticket_price() else 0 end;
$$;
revoke all on function runspot_private.crew_ticket_price_for(uuid) from public, anon, authenticated;

-- 기존 상품의 지급량은 유지합니다. 500코인 묶음에는 새 상품 ID를 씁니다.
create or replace function runspot_private.coin_pack_coins(product text)
returns integer language sql immutable set search_path = '' as $$
  select case product
    when 'coins_1100' then 100 when 'coins_3300' then 300
    when 'coins_5500_v2' then 500 when 'coins_5500' then 520
    when 'coins_11000' then 1080 when 'coins_16500' then 1650
    when 'coins_33000' then 3400 when 'coins_49900' then 5300
  end;
$$;

create or replace function runspot_private.record_coin_purchase(
  transaction text, customer uuid, product text, purchased timestamptz, store_environment text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  owner uuid;
  amount integer := runspot_private.coin_pack_coins(product);
begin
  if store_environment is distinct from (
    select s.store_environment from runspot_private.coin_economy_settings s
  ) or length(coalesce(transaction, '')) not between 1 and 200 or amount is null then
    return false;
  end if;
  select user_id into owner from runspot_private.cosmetic_customers where customer_id = customer;
  if owner is null then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('coin_transaction:' || transaction, 0));
  perform pg_advisory_xact_lock(hashtextextended('coins:' || owner::text, 0));
  insert into runspot_private.coin_purchases(
    transaction_id, user_id, product_id, coins, environment, purchased_at, refunded_at
  ) values (
    transaction, owner, product, amount, store_environment, coalesce(purchased, now()),
    (select f.refunded_at from runspot_private.coin_refunds f
     where f.environment = store_environment and f.transaction_id = transaction)
  ) on conflict (transaction_id) do nothing;
  return exists (
    select 1 from runspot_private.coin_purchases p where p.transaction_id = transaction
    and p.user_id = owner and p.product_id = product and p.environment = store_environment
  );
end;
$$;

-- 이전 웹훅의 환경 없는 환불 호출은 거부합니다.
create or replace function runspot_private.refund_coin_purchase(transaction text)
returns boolean language sql security definer set search_path = '' as $$ select false; $$;

create function runspot_private.refund_coin_purchase(transaction text, store_environment text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare owner uuid;
begin
  if store_environment is distinct from (
    select s.store_environment from runspot_private.coin_economy_settings s
  ) or length(coalesce(transaction, '')) not between 1 and 200 then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('coin_transaction:' || transaction, 0));
  select p.user_id into owner from runspot_private.coin_purchases p
  where p.transaction_id = transaction and p.environment = store_environment;
  if owner is not null then
    perform pg_advisory_xact_lock(hashtextextended('coins:' || owner::text, 0));
  end if;
  insert into runspot_private.coin_refunds(transaction_id, environment)
  values (transaction, store_environment) on conflict do nothing;
  update runspot_private.coin_purchases p set refunded_at = coalesce(p.refunded_at, now())
  where p.transaction_id = transaction and p.environment = store_environment;
  return true;
end;
$$;

create function public.refund_coin_purchase(transaction text, store_environment text)
returns boolean language sql security invoker set search_path = '' as $$
  select runspot_private.refund_coin_purchase(transaction, store_environment);
$$;
revoke all on function public.refund_coin_purchase(text,text),
  runspot_private.refund_coin_purchase(text,text) from public, anon, authenticated;
grant execute on function public.refund_coin_purchase(text,text),
  runspot_private.refund_coin_purchase(text,text) to service_role;

-- 기존 레벨 보상은 이월하고, 이후 기록 검토나 삭제가 만든 잔액 변화도 보여줍니다.
create table runspot_private.level_coin_activity (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  coins integer not null check (coins <> 0),
  balance_after integer not null check (balance_after >= 0),
  created_at timestamptz not null default now()
);
create index level_coin_activity_owner_idx on runspot_private.level_coin_activity(user_id, id desc);
alter table runspot_private.level_coin_activity enable row level security;
revoke all on runspot_private.level_coin_activity from public, anon, authenticated;

insert into runspot_private.level_coin_activity(user_id, coins, balance_after)
select user_id, coins, coins
from (
  select w.user_id, runspot_private.level_coins(
    runspot_private.level_for_xp(sum(w.xp)::integer)
  ) as coins
  from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
  where not r.review_pending and r.integrity_status<>'rejected'
  group by w.user_id
) existing where coins > 0;

create function runspot_private.log_level_coin_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := case when tg_op='DELETE' then old.user_id else new.user_id end;
  previous integer;
  current_balance integer;
begin
  if not exists(select 1 from auth.users where id=owner) then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended('coins:' || owner::text, 0));
  select a.balance_after into previous from runspot_private.level_coin_activity a
  where a.user_id=owner order by a.id desc limit 1;
  previous := coalesce(previous, 0);
  current_balance := runspot_private.level_coins(runspot_private.user_level(owner));
  if current_balance <> previous then
    insert into runspot_private.level_coin_activity(user_id,coins,balance_after)
    values(owner,current_balance-previous,current_balance);
  end if;
  return null;
end;
$$;
revoke all on function runspot_private.log_level_coin_activity() from public, anon, authenticated;
create trigger run_rewards_level_coin_activity after insert or update of xp or delete
  on runspot_private.run_rewards for each row execute function runspot_private.log_level_coin_activity();
create trigger runs_level_coin_review_activity after update of review_pending, integrity_status
  on public.runs for each row
  when (old.review_pending is distinct from new.review_pending
    or old.integrity_status is distinct from new.integrity_status)
  execute function runspot_private.log_level_coin_activity();

-- 크루가 사라져도 이미 사용한 정원 확장 비용은 구매 내역에 남깁니다.
alter table runspot_private.crew_expansions
  add column id uuid not null default gen_random_uuid(),
  drop constraint crew_expansions_pkey,
  drop constraint crew_expansions_crew_id_fkey,
  alter column crew_id drop not null,
  add primary key (id),
  add unique (crew_id),
  add foreign key (crew_id) references runspot_private.crews(id) on delete set null;

create or replace function runspot_private.coin_balance(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select runspot_private.level_coins(runspot_private.user_level(target))
    + coalesce((select sum(coins) from runspot_private.coin_purchases
        where user_id=target and refunded_at is null
        and environment=(select store_environment from runspot_private.coin_economy_settings)),0)::integer
    + coalesce((select sum(coins) from runspot_private.coin_grants where user_id=target),0)::integer
    + coalesce((select sum(coins) from runspot_private.weekly_coin_rewards where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_frames where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.crew_tickets where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_cosmetics where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.crew_expansions where user_id=target),0)::integer;
$$;

create or replace function runspot_private.wallet_json(target uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with l as (select runspot_private.user_level(target) as level,
    date_trunc('week', now() at time zone 'Asia/Seoul')::date as week_start)
  select jsonb_build_object(
    'coins',runspot_private.coin_balance(target),
    'level',l.level,
    'level_coins',runspot_private.level_coins(l.level),
    'next_reward_level',case when l.level < 99 then l.level+1 end,
    'next_reward_coins',case when l.level < 99
      then runspot_private.level_coins(l.level+1)-runspot_private.level_coins(l.level) end,
    'prices',jsonb_build_object('basic',runspot_private.frame_price('basic'),
      'aura',runspot_private.frame_price('aura'),'crew_ticket',runspot_private.crew_ticket_price_for(target),
      'crew_expansion',runspot_private.crew_expansion_price()),
    'cosmetic_prices',(select jsonb_object_agg(code, runspot_private.cosmetic_price(code))
      from unnest(array['route_neon','route_gold','route_rainbow','title_gold','title_neon',
        'title_gradient','title_crown','title_fire','bubble_mint','bubble_sunset','bubble_night','bubble_pink']) as items(code)),
    'weekly_quest',jsonb_build_object(
      'days',least(2,runspot_private.weekly_coin_days(target,l.week_start)),
      'reward',20,
      'awarded',exists(select 1 from runspot_private.weekly_coin_rewards w
        where w.user_id=target and w.week_start=l.week_start)),
    'transactions',(select coalesce(jsonb_agg(to_jsonb(entry) order by entry.at desc),'[]'::jsonb)
      from (
        select * from (
          select 'charge' as kind, p.coins, p.purchased_at as at
          from runspot_private.coin_purchases p where p.user_id=target
            and p.environment=(select store_environment from runspot_private.coin_economy_settings)
          union all
          select 'refund',-p.coins,p.refunded_at
          from runspot_private.coin_purchases p where p.user_id=target and p.refunded_at is not null
            and p.environment=(select store_environment from runspot_private.coin_economy_settings)
          union all
          select 'weekly',w.coins,w.awarded_at from runspot_private.weekly_coin_rewards w where w.user_id=target
          union all
          select 'grant',g.coins,g.created_at from runspot_private.coin_grants g where g.user_id=target
          union all
          select 'level',lca.coins,lca.created_at from runspot_private.level_coin_activity lca where lca.user_id=target
          union all
          select 'item',-f.coins,f.purchased_at from runspot_private.owned_frames f where f.user_id=target
          union all
          select 'item',-c.coins,c.purchased_at from runspot_private.owned_cosmetics c where c.user_id=target
          union all
          select 'item',-t.coins,t.purchased_at from runspot_private.crew_tickets t where t.user_id=target
          union all
          select 'item',-e.coins,e.purchased_at from runspot_private.crew_expansions e where e.user_id=target
        ) entries order by at desc limit 20
      ) entry),
    'owned',(select coalesce(jsonb_agg(frame order by frame),'[]'::jsonb)
      from runspot_private.owned_frames where user_id=target),
    'equipped',(select frame from runspot_private.frame_settings where user_id=target),
    'color',coalesce((select color from runspot_private.frame_settings where user_id=target),'#3182F6'),
    'crew_tickets',(select count(*) from runspot_private.crew_tickets where user_id=target and used_at is null),
    'in_crew',exists(select 1 from runspot_private.crew_members where user_id=target),
    'cosmetics',jsonb_build_object(
      'owned',(select coalesce(jsonb_agg(item order by item),'[]'::jsonb)
        from runspot_private.owned_cosmetics where user_id=target),
      'equipped',(select coalesce(jsonb_object_agg(slot,item),'{}'::jsonb)
        from runspot_private.equipped_cosmetics where user_id=target)))
  from l;
$$;

create or replace function runspot_private.buy_crew_ticket()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); price integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('coins:'||viewer::text,0));
  price := runspot_private.crew_ticket_price_for(viewer);
  if exists(select 1 from runspot_private.crew_tickets where user_id=viewer and used_at is null) then
    raise exception '사용하지 않은 크루 생성권이 이미 있어요.' using errcode='P0001';
  end if;
  if price > 0 and runspot_private.coin_balance(viewer) < price then
    raise exception '코인이 부족합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.crew_tickets(user_id,coins) values(viewer,price);
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 로그인한 본인의 거래만 확인할 수 있습니다.
create function runspot_private.my_coin_purchase_status(transaction text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return coalesce((
    select jsonb_build_object(
      'state',case when p.refunded_at is null then 'credited' else 'refunded' end,
      'coins',p.coins)
    from runspot_private.coin_purchases p
    where p.transaction_id=transaction and p.user_id=viewer
      and p.environment=(select store_environment from runspot_private.coin_economy_settings)
  ),jsonb_build_object('state','pending'));
end;
$$;

create function public.my_coin_purchase_status(transaction text)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_coin_purchase_status(transaction);
$$;
revoke all on function public.my_coin_purchase_status(text),
  runspot_private.my_coin_purchase_status(text) from public, anon, authenticated;
grant execute on function public.my_coin_purchase_status(text),
  runspot_private.my_coin_purchase_status(text) to authenticated;

-- 바뀐 가격을 사용자가 다시 확인하기 전에는 새 앱에서 차감하지 않습니다.
create function runspot_private.buy_cosmetic(requested_item text, expected_price integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if expected_price is distinct from runspot_private.cosmetic_price(requested_item) then
    raise exception '아이템 가격이 바뀌었습니다. 상점을 새로고침해 주세요.' using errcode='P0001';
  end if;
  return runspot_private.buy_cosmetic(requested_item);
end;
$$;
create function public.buy_cosmetic(requested_item text, expected_price integer)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.buy_cosmetic(requested_item, expected_price);
$$;
revoke all on function public.buy_cosmetic(text,integer),
  runspot_private.buy_cosmetic(text,integer) from public, anon, authenticated;
grant execute on function public.buy_cosmetic(text,integer),
  runspot_private.buy_cosmetic(text,integer) to authenticated;
notify pgrst,'reload schema';
