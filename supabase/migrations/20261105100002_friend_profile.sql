-- 친구 공개 범위를 통과한 계정의 성장 정보와 집계만 반환합니다.
create function runspot_private.friend_profile(target_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  nickname text;
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  select p.nickname into nickname
  from public.profiles p
  where p.id = target_id
    and p.nickname is not null
    and runspot_private.can_read(p.id, p.visibility)
    and exists (
      select 1 from public.friendships f
      where f.user_low = least(viewer, target_id)
        and f.user_high = greatest(viewer, target_id)
        and f.status = 'accepted'
    );
  if not found then return null; end if;

  return jsonb_build_object(
    'nickname', nickname,
    'progress', runspot_private.progress_for_xp((
      select coalesce(sum(w.xp), 0)::integer
      from runspot_private.run_rewards w join public.runs r on r.id = w.run_id
      where w.user_id = target_id and not r.review_pending and r.integrity_status <> 'rejected'
    )),
    'statistics', (
      select jsonb_build_object(
        'week_started_at', week_start,
        'weekly_distance_m', coalesce(sum(r.distance_m) filter (where r.ended_at >= week_start), 0),
        'completed_runs', count(*),
        'pace_distance_m', coalesce(sum(r.distance_m), 0),
        'pace_duration_sec', coalesce(sum(r.duration_sec), 0)
      )
      from public.runs r
      where r.user_id = target_id and r.ended_at <= now()
        and r.distance_m > 0 and r.duration_sec > 0
        and not r.review_pending and r.integrity_status <> 'rejected'
    ),
    'achievements', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'title', d.title, 'metric', d.metric, 'target', d.target,
        'progress', coalesce(a.progress, 0)
      ) order by d.target, d.code), '[]'::jsonb)
      from public.achievement_definitions d
      left join public.user_achievements a on a.achievement_code = d.code and a.user_id = target_id
      where d.code in ('first_run', 'ten_runs', 'fifty_km')
    )
  );
end;
$$;

create function public.friend_profile(target_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.friend_profile(target_id);
$$;

revoke all on function runspot_private.friend_profile(uuid), public.friend_profile(uuid)
  from public, anon, authenticated, service_role;
grant execute on function runspot_private.friend_profile(uuid), public.friend_profile(uuid)
  to authenticated;
notify pgrst, 'reload schema';
