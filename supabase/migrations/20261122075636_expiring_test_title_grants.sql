-- 테스트 칭호는 지정한 계정에 만료 시각까지 지급합니다.
create table runspot_private.test_title_grants (
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (title in ('ten_k', 'half', 'dawn', 'steady', 'crew_leader', 'together')),
  expires_at timestamptz not null,
  primary key (user_id, title)
);
alter table runspot_private.test_title_grants enable row level security;
revoke all on runspot_private.test_title_grants from public, anon, authenticated, service_role;

create or replace function runspot_private.title_progress(target uuid)
returns table(title text,progress integer,goal integer)
language sql stable security definer set search_path='' as $$
  with earned(title, progress, goal) as (
  select 'ten_k',coalesce((select max(distance_m) from public.runs
      where user_id=target and integrity_status<>'rejected'),0),10000
  union all
  select 'half',coalesce((select max(distance_m) from public.runs
      where user_id=target and integrity_status<>'rejected'),0),21097
  union all
  select 'dawn',(select count(*)::integer from public.runs
      where user_id=target and integrity_status<>'rejected'
        and extract(hour from started_at at time zone 'Asia/Seoul') < 6),10
  union all
  -- 지난주부터 거꾸로, 주간 목표를 연속으로 달성한 주 수입니다(최대 4).
  select 'steady',coalesce((
    with goal as (select kilometers*1000 as meters from runspot_private.weekly_goals
        where user_id=target and kilometers is not null),
      weeks as (
        select w,(select coalesce(sum(r.distance_m),0) from public.runs r
            where r.user_id=target and r.integrity_status<>'rejected'
              and r.started_at >= (date_trunc('week',now() at time zone 'Asia/Seoul') - (w*interval '1 week')) at time zone 'Asia/Seoul'
              and r.started_at < (date_trunc('week',now() at time zone 'Asia/Seoul') - ((w-1)*interval '1 week')) at time zone 'Asia/Seoul') as meters
        from generate_series(1,4) w)
    select coalesce(min(w)-1,4)::integer from weeks,goal where weeks.meters < goal.meters
  ),0)*case when exists(select 1 from runspot_private.weekly_goals where user_id=target and kilometers is not null) then 1 else 0 end,4
  union all
  select 'crew_leader',coalesce((select max((select count(*) from runspot_private.crew_members m where m.crew_id=c.id))::integer
      from runspot_private.crews c where c.owner_id=target),0),10
  union all
  select 'together',(select count(*)::integer from runspot_private.running_group_members
      where user_id=target and status='finished'),10
  )
  select e.title,
    case when g.user_id is null then e.progress else greatest(e.progress, e.goal) end,
    e.goal
  from earned e
  left join runspot_private.test_title_grants g
    on g.user_id = target and g.title = e.title and g.expires_at > now();
$$;
