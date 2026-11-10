-- 코인과 코인으로 사는 테두리입니다. 잔액은 서버 기록으로만 계산하며 앱은 조회와 요청만 합니다.
-- 잔액 = 레벨 보상 + 결제로 산 코인(환불 제외) + 운영자 지급 - 사용한 코인

-- 스토어 결제는 RevenueCat 웹훅(coin-webhook 함수)만 기록합니다. 같은 거래는 한 번만 반영합니다.
create table runspot_private.coin_purchases (
  transaction_id text primary key check (length(transaction_id) between 1 and 200),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  coins integer not null check (coins > 0),
  environment text not null default 'PRODUCTION',
  purchased_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  refunded_at timestamptz
);
create index coin_purchases_user on runspot_private.coin_purchases(user_id);

-- 운영자가 SQL 편집기에서 직접 넣는 지급·회수 기록입니다(이벤트 보상, 고객 문의 보상, 테스트).
create table runspot_private.coin_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  coins integer not null check (coins <> 0),
  reason text not null check (length(btrim(reason)) between 1 and 200),
  created_at timestamptz not null default now()
);
create index coin_grants_user on runspot_private.coin_grants(user_id);

create table runspot_private.owned_frames (
  user_id uuid not null references auth.users(id) on delete cascade,
  frame text not null check (frame in ('basic','aura')),
  coins integer not null check (coins >= 0),
  purchased_at timestamptz not null default now(),
  primary key(user_id,frame)
);

-- 착용한 테두리와 색입니다. 색은 #RRGGBB 형식이면 자유롭게 고를 수 있습니다.
create table runspot_private.frame_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  frame text check (frame in ('basic','aura')),
  color text not null default '#3182F6' check (color ~ '^#[0-9A-F]{6}$'),
  updated_at timestamptz not null default now()
);

alter table runspot_private.coin_purchases enable row level security;
alter table runspot_private.coin_grants enable row level security;
alter table runspot_private.owned_frames enable row level security;
alter table runspot_private.frame_settings enable row level security;
revoke all on runspot_private.coin_purchases,runspot_private.coin_grants,
  runspot_private.owned_frames,runspot_private.frame_settings from public,anon,authenticated;

-- 판매 가격(코인)입니다. 1,100원 = 100코인 기준으로 기본 테두리는 약 3,300원, 오라 테두리는 약 15,400원입니다.
create function runspot_private.frame_price(frame text)
returns integer language sql immutable set search_path = '' as $$
  select case frame when 'basic' then 300 when 'aura' then 1400 end;
$$;

-- 스토어 상품별 지급 코인입니다. 큰 묶음일수록 보너스를 더 줍니다.
create function runspot_private.coin_pack_coins(product text)
returns integer language sql immutable set search_path = '' as $$
  select case product
    when 'coins_1100' then 100
    when 'coins_3300' then 300
    when 'coins_5500' then 520
    when 'coins_11000' then 1080
    when 'coins_16500' then 1650
    when 'coins_33000' then 3400
    when 'coins_49900' then 5300
  end;
$$;

-- 레벨이 오를 때마다 10코인, 5의 배수 레벨에는 50코인을 더 줍니다. Lv 1은 0코인입니다.
create function runspot_private.level_coins(level integer)
returns integer language sql immutable set search_path = '' as $$
  select 10*(greatest(level,1)-1) + 50*(greatest(level,1)/5);
$$;

-- my_progress와 같은 기준(검토 대기·거절 기록 제외)으로 레벨을 계산합니다.
create function runspot_private.user_level(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select runspot_private.level_for_xp((select coalesce(sum(w.xp),0)::integer
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
    where w.user_id=target and not r.review_pending and r.integrity_status<>'rejected'));
$$;

create function runspot_private.coin_balance(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select runspot_private.level_coins(runspot_private.user_level(target))
    + coalesce((select sum(coins) from runspot_private.coin_purchases
        where user_id=target and refunded_at is null),0)::integer
    + coalesce((select sum(coins) from runspot_private.coin_grants where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_frames where user_id=target),0)::integer;
$$;

create function runspot_private.wallet_json(target uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with l as (select runspot_private.user_level(target) as level)
  select jsonb_build_object(
    'coins',runspot_private.coin_balance(target),
    'level',l.level,
    'level_coins',runspot_private.level_coins(l.level),
    'next_reward_level',case when l.level < 99 then l.level+1 end,
    'next_reward_coins',case when l.level < 99
      then runspot_private.level_coins(l.level+1)-runspot_private.level_coins(l.level) end,
    'prices',jsonb_build_object('basic',runspot_private.frame_price('basic'),
      'aura',runspot_private.frame_price('aura')),
    'owned',(select coalesce(jsonb_agg(frame order by frame),'[]'::jsonb)
      from runspot_private.owned_frames where user_id=target),
    'equipped',(select frame from runspot_private.frame_settings where user_id=target),
    'color',coalesce((select color from runspot_private.frame_settings where user_id=target),'#3182F6'))
  from l;
$$;

create function runspot_private.my_wallet()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  return runspot_private.wallet_json(runspot_private.require_board_viewer());
end;
$$;

-- 같은 사람의 동시 구매를 직렬화해 잔액보다 많이 쓰지 못하게 합니다. 이미 가진 테두리는 다시 사지 않습니다.
create function runspot_private.buy_frame(requested_frame text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); price integer;
begin
  price := runspot_private.frame_price(requested_frame);
  if price is null then raise exception '테두리 종류를 확인해 주세요.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('coins:'||viewer::text,0));
  if exists(select 1 from runspot_private.owned_frames where user_id=viewer and frame=requested_frame) then
    return runspot_private.wallet_json(viewer);
  end if;
  if runspot_private.coin_balance(viewer) < price then
    raise exception '코인이 부족합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.owned_frames(user_id,frame,coins) values(viewer,requested_frame,price);
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 가진 테두리만 착용합니다. requested_frame이 null이면 해제하고, 색은 그대로 둡니다.
create function runspot_private.set_frame(requested_frame text,requested_color text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); color_value text := upper(btrim(requested_color));
begin
  if color_value is null or color_value !~ '^#[0-9A-F]{6}$' then
    raise exception '색을 다시 골라 주세요.' using errcode='22023';
  end if;
  if requested_frame is not null and not exists(select 1 from runspot_private.owned_frames
    where user_id=viewer and frame=requested_frame) then
    raise exception '가지고 있는 테두리만 착용할 수 있습니다.' using errcode='42501';
  end if;
  insert into runspot_private.frame_settings(user_id,frame,color) values(viewer,requested_frame,color_value)
  on conflict(user_id) do update set frame=excluded.frame,color=excluded.color,updated_at=now();
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 웹훅 전용: 결제 계정 식별자를 사용자로 바꿔 코인을 기록합니다. 처리하지 않은 요청은 false입니다.
create function runspot_private.record_coin_purchase(transaction text,customer uuid,product text,
  purchased timestamptz,store_environment text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare owner uuid; amount integer := runspot_private.coin_pack_coins(product);
begin
  if transaction is null or amount is null then return false; end if;
  select user_id into owner from runspot_private.cosmetic_customers where customer_id=customer;
  if owner is null then return false; end if;
  insert into runspot_private.coin_purchases(transaction_id,user_id,product_id,coins,environment,purchased_at)
  values(transaction,owner,product,amount,coalesce(store_environment,'PRODUCTION'),coalesce(purchased,now()))
  on conflict(transaction_id) do nothing;
  return true;
end;
$$;

-- 웹훅 전용: 환불된 결제의 코인을 잔액에서 뺍니다. 이미 쓴 코인 때문에 잔액이 음수가 되면 새 구매가 막힙니다.
create function runspot_private.refund_coin_purchase(transaction text)
returns boolean language sql security definer set search_path = '' as $$
  with refunded as (update runspot_private.coin_purchases set refunded_at=coalesce(refunded_at,now())
    where transaction_id=transaction returning 1)
  select exists(select 1 from refunded);
$$;

create function public.my_wallet() returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_wallet(); $$;
create function public.buy_frame(requested_frame text) returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.buy_frame(requested_frame); $$;
create function public.set_frame(requested_frame text,requested_color text) returns jsonb language sql
security invoker set search_path = ''
as $$ select runspot_private.set_frame(requested_frame,requested_color); $$;
create function public.record_coin_purchase(transaction text,customer uuid,product text,purchased timestamptz,
  store_environment text) returns boolean language sql security invoker set search_path = ''
as $$ select runspot_private.record_coin_purchase(transaction,customer,product,purchased,store_environment); $$;
create function public.refund_coin_purchase(transaction text) returns boolean language sql security invoker
set search_path = '' as $$ select runspot_private.refund_coin_purchase(transaction); $$;

revoke all on function
  runspot_private.frame_price(text),runspot_private.coin_pack_coins(text),runspot_private.level_coins(integer),
  runspot_private.user_level(uuid),runspot_private.coin_balance(uuid),runspot_private.wallet_json(uuid),
  runspot_private.my_wallet(),runspot_private.buy_frame(text),runspot_private.set_frame(text,text),
  runspot_private.record_coin_purchase(text,uuid,text,timestamptz,text),runspot_private.refund_coin_purchase(text),
  public.my_wallet(),public.buy_frame(text),public.set_frame(text,text),
  public.record_coin_purchase(text,uuid,text,timestamptz,text),public.refund_coin_purchase(text)
  from public,anon,authenticated,service_role;
grant execute on function runspot_private.my_wallet(),runspot_private.buy_frame(text),runspot_private.set_frame(text,text),
  public.my_wallet(),public.buy_frame(text),public.set_frame(text,text) to authenticated;
-- 결제 기록 함수는 웹훅이 쓰는 서버 전용 키로만 실행합니다.
grant execute on function runspot_private.record_coin_purchase(text,uuid,text,timestamptz,text),
  runspot_private.refund_coin_purchase(text),
  public.record_coin_purchase(text,uuid,text,timestamptz,text),public.refund_coin_purchase(text) to service_role;
notify pgrst,'reload schema';
