-- 공유 카드는 착용 칸에 넣지 않고, 공유 화면에서 보유한 카드만 고릅니다.
create or replace function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('share_minimal','share_night') then 'share_card'
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
  end;
$$;

create or replace function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path = '' as $$
  select case item
    when 'share_minimal' then 100 when 'share_night' then 200
    when 'route_neon' then 150 when 'route_gold' then 300 when 'route_rainbow' then 500
    when 'title_gold' then 150 when 'title_neon' then 200 when 'title_gradient' then 250
    when 'title_crown' then 150 when 'title_fire' then 150
    when 'bubble_mint' then 100 when 'bubble_sunset' then 200 when 'bubble_night' then 150 when 'bubble_pink' then 150
  end;
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
        'title_gradient','title_crown','title_fire','bubble_mint','bubble_sunset','bubble_night','bubble_pink','share_minimal','share_night']) as items(code)),
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

notify pgrst,'reload schema';
