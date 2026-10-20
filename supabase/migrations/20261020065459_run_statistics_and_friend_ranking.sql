-- 주간 범위는 러닝 종료 시각을 한국 시간 월요일 0시 기준으로 판정합니다.
create index runs_owner_ended_at on public.runs(user_id, ended_at);

create function runspot_private.my_run_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 개인 통계는 검증 여부와 관계없이 저장된 모든 완료 기록을 집계합니다.
  -- 이동 거리나 활동 시간이 없는 기록은 페이스 계산에서만 제외합니다.
  return (
    select jsonb_build_object(
      'week_started_at', week_start,
      'weekly_distance_m', coalesce(sum(r.distance_m) filter (
        where r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
          and r.ended_at <= now()), 0),
      'completed_runs', count(*),
      'pace_distance_m', coalesce(sum(r.distance_m) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0),
      'pace_duration_sec', coalesce(sum(r.duration_sec) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0)
    ) from public.runs r where r.user_id=viewer and r.ended_at <= now()
  );
end;
$$;

create function runspot_private.friend_weekly_ranking()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if not runspot_private.can_interact() then
    return jsonb_build_object('can_interact', false, 'week_started_at', week_start, 'entries', '[]'::jsonb);
  end if;
  return (
    with participants as (
      select p.id, p.nickname from public.profiles p where p.id=viewer
      union all
      select p.id, p.nickname from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      where viewer in (f.user_low,f.user_high) and f.status='accepted'
        and p.nickname is not null and runspot_private.email_verified(p.id)
        and runspot_private.can_read(p.id,p.visibility)
    ), totals as (
      select p.id, p.nickname, coalesce(sum(r.distance_m),0) as distance_m
      from participants p left join public.runs r on r.user_id=p.id
        and r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
        and r.ended_at <= now() and r.integrity_status <> 'rejected'
      group by p.id,p.nickname
    ), ranked as (
      select rank() over(order by t.distance_m desc) as rank,
        t.id, t.nickname, t.distance_m, t.id=viewer as is_me from totals t
    )
    select jsonb_build_object('can_interact',true,'week_started_at',week_start,
      'entries',coalesce(jsonb_agg(jsonb_build_object(
        'rank',r.rank,'nickname',r.nickname,'distance_m',r.distance_m,'is_me',r.is_me
      ) order by r.distance_m desc,r.nickname,r.id),'[]'::jsonb)) from ranked r
  );
end;
$$;

-- 원본 기록과 경로의 본인 전용 정책은 유지하고 제한된 집계만 공개합니다.
create function public.my_run_statistics()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_run_statistics();
$$;
create function public.friend_weekly_ranking()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.friend_weekly_ranking();
$$;
revoke all on function runspot_private.my_run_statistics(),runspot_private.friend_weekly_ranking(),
  public.my_run_statistics(),public.friend_weekly_ranking() from public,anon,authenticated;
grant execute on function runspot_private.my_run_statistics(),runspot_private.friend_weekly_ranking(),
  public.my_run_statistics(),public.friend_weekly_ranking() to authenticated;
notify pgrst, 'reload schema';
