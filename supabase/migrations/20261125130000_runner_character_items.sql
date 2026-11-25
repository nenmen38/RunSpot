-- 내 러너 캐릭터 꾸미기: 모자·선글라스·상의·하의·팔토시·운동화를 코인으로 사서 캐릭터에 입힙니다.
-- 기존 꾸미기(경로 색·칭호 모양·말풍선·공유 카드)와 같은 보유·착용 방식을 쓰고, 칸마다 하나씩 착용합니다.

create or replace function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('share_minimal','share_night') then 'share_card'
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
    when item in ('char_cap_blue','char_cap_black','char_visor_white','char_headband_red') then 'char_head'
    when item in ('char_glasses_black','char_glasses_mirror') then 'char_eyes'
    when item in ('char_singlet_orange','char_tee_mint','char_tee_navy') then 'char_top'
    when item in ('char_shorts_black','char_shorts_blue') then 'char_bottom'
    when item in ('char_sleeves_black','char_sleeves_neon') then 'char_sleeves'
    when item in ('char_shoes_red','char_shoes_neon','char_shoes_carbon') then 'char_shoes'
  end;
$$;

-- 가격(코인): 머리띠 100 · 모자·쇼츠·팔토시 150~200 · 선글라스·상의 200~250 · 운동화 250~450.
create or replace function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path = '' as $$
  select case item
    when 'share_minimal' then 100 when 'share_night' then 200
    when 'route_neon' then 150 when 'route_gold' then 300 when 'route_rainbow' then 500
    when 'title_gold' then 150 when 'title_neon' then 200 when 'title_gradient' then 250
    when 'title_crown' then 150 when 'title_fire' then 150
    when 'bubble_mint' then 100 when 'bubble_sunset' then 200 when 'bubble_night' then 150 when 'bubble_pink' then 150
    when 'char_cap_blue' then 150
    when 'char_cap_black' then 150
    when 'char_visor_white' then 200
    when 'char_headband_red' then 100
    when 'char_glasses_black' then 200
    when 'char_glasses_mirror' then 250
    when 'char_singlet_orange' then 200
    when 'char_tee_mint' then 200
    when 'char_tee_navy' then 250
    when 'char_shorts_black' then 150
    when 'char_shorts_blue' then 150
    when 'char_sleeves_black' then 150
    when 'char_sleeves_neon' then 200
    when 'char_shoes_red' then 250
    when 'char_shoes_neon' then 300
    when 'char_shoes_carbon' then 450
  end;
$$;

-- 착용 칸에 캐릭터 칸을 더합니다.
do $do$
declare item record;
begin
  for item in select conname from pg_constraint
    where conrelid='runspot_private.equipped_cosmetics'::regclass and contype='c'
      and pg_get_constraintdef(oid) like '%slot = ANY%'
  loop
    execute format('alter table runspot_private.equipped_cosmetics drop constraint %I',item.conname);
  end loop;
end;
$do$;
alter table runspot_private.equipped_cosmetics add constraint equipped_cosmetics_slot_check
  check (slot in ('route','title_style','aura_effect','chat_bubble','char_head','char_eyes','char_top','char_bottom','char_sleeves','char_shoes'));

create or replace function runspot_private.equip_cosmetic(requested_slot text,requested_item text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if requested_slot is null or requested_slot not in ('route','title_style','aura_effect','chat_bubble','char_head','char_eyes','char_top','char_bottom','char_sleeves','char_shoes') then
    raise exception '착용할 곳을 확인해 주세요.' using errcode='22023';
  end if;
  if requested_item is null then
    delete from runspot_private.equipped_cosmetics where user_id=viewer and slot=requested_slot;
    return runspot_private.wallet_json(viewer);
  end if;
  if runspot_private.cosmetic_slot(requested_item) is distinct from requested_slot then
    raise exception '이 칸에 착용할 수 없는 아이템이에요.' using errcode='22023';
  end if;
  if not exists(select 1 from runspot_private.owned_cosmetics where user_id=viewer and item=requested_item) then
    raise exception '가진 아이템만 착용할 수 있습니다.' using errcode='P0001';
  end if;
  insert into runspot_private.equipped_cosmetics(user_id,slot,item) values(viewer,requested_slot,requested_item)
  on conflict(user_id,slot) do update set item=excluded.item,updated_at=now();
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 지갑 정보의 판매 목록(cosmetic_prices)에 캐릭터 아이템을 더합니다. 나머지는 이전과 같습니다.
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
        'title_gradient','title_crown','title_fire','bubble_mint','bubble_sunset','bubble_night','bubble_pink','share_minimal','share_night',
        'char_cap_blue','char_cap_black','char_visor_white','char_headband_red','char_glasses_black','char_glasses_mirror','char_singlet_orange','char_tee_mint','char_tee_navy','char_shorts_black','char_shorts_blue','char_sleeves_black','char_sleeves_neon','char_shoes_red','char_shoes_neon','char_shoes_carbon']) as items(code)),
    'weekly_quest',jsonb_build_object(
      'days',least(2,runspot_private.weekly_coin_days(target,l.week_start)),
      'reward',20,
      'awarded',exists(select 1 from runspot_private.weekly_coin_rewards w
        where w.user_id=target and w.week_start=l.week_start and w.quest='two_days')),
    'weekly_quests',(
      select jsonb_agg(jsonb_build_object(
        'code',q.quest,'progress',least(q.progress,q.goal),'goal',q.goal,
        'reward',q.coins,'awarded',w.user_id is not null
      ) order by q.display_order)
      from runspot_private.weekly_coin_quests(target,l.week_start) q
      left join runspot_private.weekly_coin_rewards w
        on w.user_id=target and w.week_start=l.week_start and w.quest=q.quest
    ),
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

notify pgrst,'reload schema';
