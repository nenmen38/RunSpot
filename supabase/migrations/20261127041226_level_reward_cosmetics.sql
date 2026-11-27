-- 캐릭터 성장 보상: 레벨 5·10·20에 도달하면 한정 캐릭터 아이템을 자동으로 선물합니다.
-- 골드 헤어밴드(레벨 5), 무지개 러닝화(레벨 10), 챔피언 골드 싱글렛(레벨 20)은 상점에서 살 수 없고 레벨로만 받습니다.

create or replace function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('share_minimal','share_night') then 'share_card'
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
    when item in ('char_cap_blue','char_cap_black','char_visor_white','char_headband_red','char_headband_gold') then 'char_head'
    when item in ('char_glasses_black','char_glasses_mirror') then 'char_eyes'
    when item in ('char_singlet_orange','char_tee_mint','char_tee_navy','char_singlet_gold') then 'char_top'
    when item in ('char_shorts_black','char_shorts_blue') then 'char_bottom'
    when item in ('char_sleeves_black','char_sleeves_neon') then 'char_sleeves'
    when item in ('char_shoes_red','char_shoes_neon','char_shoes_carbon','char_shoes_rainbow') then 'char_shoes'
  end;
$$;

-- 레벨 보상 아이템과 받을 수 있는 레벨입니다. 가격(cosmetic_price)이 없으므로 코인으로는 살 수 없습니다.
create function runspot_private.cosmetic_unlock_level(item text)
returns integer language sql immutable set search_path = '' as $$
  select case item
    when 'char_headband_gold' then 5
    when 'char_shoes_rainbow' then 10
    when 'char_singlet_gold' then 20
  end;
$$;
revoke all on function runspot_private.cosmetic_unlock_level(text) from public, anon, authenticated;

-- 지금 레벨까지의 보상 아이템을 0코인으로 넣어 줍니다(이미 있으면 그대로).
create function runspot_private.grant_level_cosmetics(target uuid)
returns void language sql security definer set search_path = '' as $$
  insert into runspot_private.owned_cosmetics(user_id, item, coins)
  select target, items.code, 0
  from unnest(array['char_headband_gold','char_shoes_rainbow','char_singlet_gold']) as items(code)
  where runspot_private.cosmetic_unlock_level(items.code) <= runspot_private.user_level(target)
  on conflict (user_id, item) do nothing;
$$;
revoke all on function runspot_private.grant_level_cosmetics(uuid) from public, anon, authenticated;

create or replace function runspot_private.log_level_coin_activity()
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
  -- 레벨 보상 캐릭터 아이템(레벨 5·10·20)을 선물합니다.
  perform runspot_private.grant_level_cosmetics(owner);
  return null;
end;
$$;

-- 이미 레벨이 높은 사람에게도 지금 바로 선물합니다.
select runspot_private.grant_level_cosmetics(u.user_id)
from (select distinct user_id from runspot_private.run_rewards) u
where exists(select 1 from auth.users where id = u.user_id);

-- 지갑 정보: 레벨 보상 아이템 목록(level_cosmetics)을 더하고, 0코인 선물은 구매 내역에서 뺍니다.
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
          select 'item',-c.coins,c.purchased_at from runspot_private.owned_cosmetics c where c.user_id=target and c.coins>0
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
    'level_cosmetics',(select jsonb_object_agg(code, runspot_private.cosmetic_unlock_level(code))
      from unnest(array['char_headband_gold','char_shoes_rainbow','char_singlet_gold']) as items(code)),
    'cosmetics',jsonb_build_object(
      'owned',(select coalesce(jsonb_agg(item order by item),'[]'::jsonb)
        from runspot_private.owned_cosmetics where user_id=target),
      'equipped',(select coalesce(jsonb_object_agg(slot,item),'{}'::jsonb)
        from runspot_private.equipped_cosmetics where user_id=target)))
  from l;
$$;

notify pgrst, 'reload schema';
