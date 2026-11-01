-- 기존 통계 응답에 본인 전용 성장 추이를 추가합니다. 기존 집계 필드와 권한은 유지합니다.
create or replace function runspot_private.my_run_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 개인 거리·페이스는 원본을 보존하고 완료 횟수만 업적과 같은 인정 기준을 따릅니다.
  return (
    select jsonb_build_object(
      'week_started_at', week_start,
      'weekly_distance_m', coalesce(sum(r.distance_m) filter (
        where r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
          and r.ended_at <= now()), 0),
      'completed_runs', count(*) filter(where r.distance_m>0 and r.duration_sec>0 and not r.review_pending and r.integrity_status<>'rejected'),
      'pace_distance_m', coalesce(sum(r.distance_m) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0),
      'pace_duration_sec', coalesce(sum(r.duration_sec) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0)
    ) from public.runs r where r.user_id=viewer and r.ended_at <= now()
  ) || (
    with eligible as materialized (
      select r.* from public.runs r
      where r.user_id=viewer and r.ended_at<=now()
        and r.distance_m>0 and r.duration_sec>0
        and not r.review_pending and r.integrity_status<>'rejected'
    ), months as (
      select generate_series(
        date_trunc('month',now() at time zone 'Asia/Seoul')-interval '11 months',
        date_trunc('month',now() at time zone 'Asia/Seoul'),interval '1 month') as month
    ), monthly as (
      select m.month,coalesce(sum(r.distance_m),0) as distance_m,count(r.id) as runs
      from months m left join eligible r
        on r.ended_at>=m.month at time zone 'Asia/Seoul'
        and r.ended_at<(m.month+interval '1 month') at time zone 'Asia/Seoul'
      group by m.month
    ), splits as (
      select r.id,r.ended_at,s.ordinality as ordinal,
        (s.value->>'distance_m')::numeric as metres,
        (s.value->>'duration_us')::bigint as micros
      from eligible r cross join lateral jsonb_array_elements(r.split_data) with ordinality s
    ), windows as (
      -- 1km 경계에서 시작하는 연속 완성 구간만 비교하며 끝의 미완성 구간은 제외합니다.
      select id,ended_at,ordinal,
        count(*) over five as count5,min(metres) over five as min5,
        min(micros) over five as positive5,sum(micros) over five as time5,
        count(*) over ten as count10,min(metres) over ten as min10,
        min(micros) over ten as positive10,sum(micros) over ten as time10
      from splits
      window five as (partition by id order by ordinal rows between current row and 4 following),
        ten as (partition by id order by ordinal rows between current row and 9 following)
    )
    select jsonb_build_object('growth',jsonb_build_object(
      'monthly_distances',(select jsonb_agg(jsonb_build_object(
        'month',to_char(month,'YYYY-MM'),'distance_m',distance_m,'completed_runs',runs) order by month) from monthly),
      'longest_run',(select jsonb_build_object('distance_m',distance_m,'ended_at',ended_at)
        from eligible order by distance_m desc,ended_at,id limit 1),
      'best_5k',(select jsonb_build_object('duration_us',time5,'ended_at',ended_at)
        from windows where count5=5 and min5=1000 and positive5>0 order by time5,ended_at,id,ordinal limit 1),
      'best_10k',(select jsonb_build_object('duration_us',time10,'ended_at',ended_at)
        from windows where count10=10 and min10=1000 and positive10>0 order by time10,ended_at,id,ordinal limit 1)
    ))
  );
end;
$$;
notify pgrst, 'reload schema';
