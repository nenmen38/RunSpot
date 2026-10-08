-- 이동하지 않은 러닝도 개인 기록으로 보존합니다. 공개 게시물 제약은 유지합니다.
alter table public.runs drop constraint runs_distance_m_check;
alter table public.runs add constraint runs_distance_m_check check (distance_m >= 0);
alter table public.runs drop constraint runs_duration_sec_check;
alter table public.runs add constraint runs_duration_sec_check check (duration_sec >= 0);

-- 직접 쓰기 권한은 부여하지 않고 현재 로그인한 사용자의 개인 기록만 저장합니다.
create function public.save_my_run(
  client_id uuid,
  start_time timestamptz,
  end_time timestamptz,
  distance_metres integer,
  active_seconds integer
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  saved public.runs;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode = '42501';
  end if;
  if client_id is null or start_time is null or end_time is null
    or not isfinite(start_time) or not isfinite(end_time)
    or end_time <= start_time or end_time > now() + interval '5 minutes'
    or end_time - start_time > interval '7 days'
    or distance_metres is null or distance_metres < 0 or distance_metres > 1000000
    or active_seconds is null or active_seconds < 0
    or active_seconds > extract(epoch from end_time - start_time) + 1 then
    raise exception '러닝 기록의 거리, 시간 또는 날짜가 올바르지 않습니다.' using errcode = '22023';
  end if;

  insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
  values(owner_id,client_id,start_time,end_time,distance_metres,active_seconds)
  on conflict(user_id,client_run_id) do nothing;

  select * into strict saved from public.runs
  where user_id=owner_id and client_run_id=client_id;
  if saved.started_at <> start_time or saved.ended_at <> end_time
    or saved.distance_m <> distance_metres or saved.duration_sec <> active_seconds
    or saved.route_id is not null then
    raise exception '이미 저장된 기록과 재시도 내용이 다릅니다.' using errcode = '22023';
  end if;

  -- 개인 측정값을 저장할 뿐 검증 완료나 랭킹 참여로 처리하지 않습니다.
  return jsonb_build_object(
    'id', saved.id, 'client_run_id', saved.client_run_id,
    'started_at', saved.started_at, 'ended_at', saved.ended_at,
    'distance_m', saved.distance_m, 'duration_sec', saved.duration_sec
  );
end;
$$;
revoke all on function public.save_my_run(uuid,timestamptz,timestamptz,integer,integer) from public,anon,authenticated;
grant execute on function public.save_my_run(uuid,timestamptz,timestamptz,integer,integer) to authenticated;
