-- 주별 장부를 퀘스트별로 나누고 기존 이틀 달리기 보상을 보존합니다.
alter table runspot_private.weekly_coin_rewards
  add column quest text not null default 'two_days',
  drop constraint weekly_coin_rewards_pkey,
  drop constraint weekly_coin_rewards_coins_check,
  add primary key (user_id, week_start, quest),
  add check ((quest='two_days' and coins=20)
    or (quest in ('single_3k','total_8k') and coins=5));

create function runspot_private.weekly_coin_quests(target uuid, week_start date)
returns table(display_order integer, quest text, progress integer, goal integer, coins integer)
language sql stable set search_path = '' as $$
  with eligible as (
    select r.distance_m, (r.started_at at time zone 'Asia/Seoul')::date as run_day
    from public.runs r join runspot_private.run_rewards w on w.run_id=r.id
    where r.user_id=target and r.distance_m>=1000 and w.xp>0
      and not r.review_pending and r.integrity_status<>'rejected'
      and (r.motion_evidence is not null or r.integrity_status='verified')
      and r.started_at>=greatest(week_start::timestamp at time zone 'Asia/Seoul',
        (select quests_start_at from runspot_private.coin_economy_settings))
      and r.started_at<(week_start+7)::timestamp at time zone 'Asia/Seoul'
      and r.ended_at<=now()
  ), totals as (
    select count(distinct run_day)::integer as days,
      coalesce(max(distance_m),0)::integer as longest,
      least(8000,coalesce(sum(distance_m),0))::integer as distance
    from eligible
  )
  select q.* from totals t cross join lateral (values
    (1,'two_days',t.days,2,20),
    (2,'single_3k',t.longest,3000,5),
    (3,'total_8k',t.distance,8000,5)
  ) q(display_order,quest,progress,goal,coins);
$$;
revoke all on function runspot_private.weekly_coin_quests(uuid,date)
  from public,anon,authenticated,service_role;

create or replace function runspot_private.award_weekly_coins()
returns trigger language plpgsql security definer set search_path = '' as $$
declare reward_week date;
begin
  select (date_trunc('week',r.started_at at time zone 'Asia/Seoul'))::date into reward_week
  from public.runs r
  where r.id=new.run_id and r.distance_m>=1000
    and (r.motion_evidence is not null or r.integrity_status='verified');
  if reward_week is null then return null; end if;

  insert into runspot_private.weekly_coin_rewards(user_id,week_start,quest,coins)
  select new.user_id,reward_week,q.quest,q.coins
  from runspot_private.weekly_coin_quests(new.user_id,reward_week) q
  where q.progress>=q.goal
  on conflict do nothing;
  return null;
end;
$$;

-- 이번 주에 이미 인정된 기록도 새 퀘스트에 반영합니다.
with week as (
  select date_trunc('week',now() at time zone 'Asia/Seoul')::date as start_date
), active as (
  select distinct r.user_id,w.start_date from public.runs r cross join week w
  where r.started_at>=w.start_date::timestamp at time zone 'Asia/Seoul'
    and r.started_at<(w.start_date+7)::timestamp at time zone 'Asia/Seoul'
    and r.distance_m>=1000
)
insert into runspot_private.weekly_coin_rewards(user_id,week_start,quest,coins)
select a.user_id,a.start_date,q.quest,q.coins
from active a cross join lateral runspot_private.weekly_coin_quests(a.user_id,a.start_date) q
where q.progress>=q.goal
on conflict do nothing;

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
