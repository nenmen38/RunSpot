-- 월간·연간 러닝 리포트(연말 결산)를 한 번에 계산합니다. 내 기록만 읽습니다.
-- 검토 중·거절·숨긴 기록은 빼고, 날짜는 한국 시간 기준입니다.
create function runspot_private.my_running_report(period text, starts date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  first_day date;
  last_day date;
  previous_first date;
  result jsonb;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode = '42501';
  end if;
  if period not in ('month', 'year') or starts is null then
    raise exception '리포트 기간을 확인해 주세요.' using errcode = '22023';
  end if;
  first_day := date_trunc(period, starts)::date;
  last_day := (first_day + case when period = 'year' then interval '1 year' else interval '1 month' end)::date;
  previous_first := (first_day - case when period = 'year' then interval '1 year' else interval '1 month' end)::date;

  with mine as (
    select r.id, r.distance_m, r.duration_sec, r.ended_at,
      (r.ended_at at time zone 'Asia/Seoul') as local_end
    from public.runs r
    where r.user_id = viewer and not r.review_pending and r.integrity_status <> 'rejected'
      and not r.hidden
      and (r.ended_at at time zone 'Asia/Seoul')::date >= previous_first
      and (r.ended_at at time zone 'Asia/Seoul')::date < last_day
  ), now_runs as (
    select * from mine where local_end::date >= first_day
  )
  select jsonb_build_object(
    'period', period,
    'starts', first_day,
    'runs', (select count(*) from now_runs),
    'distance_m', (select coalesce(sum(distance_m), 0) from now_runs),
    'duration_sec', (select coalesce(sum(duration_sec), 0) from now_runs),
    'active_days', (select count(distinct local_end::date) from now_runs),
    'previous_distance_m', (select coalesce(sum(distance_m), 0) from mine where local_end::date < first_day),
    'longest', (select jsonb_build_object('distance_m', distance_m, 'ended_at', ended_at)
      from now_runs order by distance_m desc, ended_at limit 1),
    -- 1km 이상 달린 기록 중 가장 빠른 평균 페이스(초/km)입니다.
    'fastest_pace_sec', (select min(round(duration_sec * 1000.0 / distance_m))::integer
      from now_runs where distance_m >= 1000),
    -- 연간: 달마다, 월간: 주(1~5주차)마다 달린 거리입니다.
    'buckets', (
      select coalesce(jsonb_agg(coalesce(b.meters, 0) order by s.idx), '[]'::jsonb)
      from generate_series(1, case when period = 'year' then 12 else 5 end) s(idx)
      left join (
        select case when period = 'year' then extract(month from local_end)::int
          else least(5, ((extract(day from local_end)::int - 1) / 7) + 1) end as idx,
          sum(distance_m) as meters
        from now_runs group by 1
      ) b on b.idx = s.idx
    ),
    -- 가장 자주 달린 요일(1=월~7=일)과 시간대입니다.
    'favorite_weekday', (select extract(isodow from local_end)::int from now_runs
      group by 1 order by count(*) desc, 1 limit 1),
    'favorite_time', (select case
        when h between 5 and 10 then 'morning'
        when h between 11 and 16 then 'afternoon'
        when h between 17 and 21 then 'evening'
        else 'night' end
      from (select extract(hour from local_end)::int as h from now_runs) t
      group by 1 order by count(*) desc, 1 limit 1),
    -- 함께 달리기에서 같이 완주한 다른 러너 수입니다.
    'companions', (
      select count(distinct other.user_id)
      from runspot_private.running_group_members me
      join now_runs n on n.id = me.run_id
      join runspot_private.running_group_members other
        on other.group_id = me.group_id and other.user_id <> viewer and other.run_id is not null
      where me.user_id = viewer
    )
  ) into result;
  return result;
end;
$$;
create function public.my_running_report(period text, starts date)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_running_report(period, starts); $$;
revoke all on function runspot_private.my_running_report(text, date), public.my_running_report(text, date)
  from public, anon, authenticated;
grant execute on function runspot_private.my_running_report(text, date), public.my_running_report(text, date)
  to authenticated;
notify pgrst, 'reload schema';
