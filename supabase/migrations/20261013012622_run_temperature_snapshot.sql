-- 기존 기록은 기온을 추정해 채우지 않습니다. 관측 시각과 기온은 함께 보존합니다.
alter table public.runs add column temperature_c double precision,
  add column temperature_observed_at timestamptz,
  add constraint runs_temperature_check check (
    (temperature_c is null and temperature_observed_at is null) or
    (temperature_c is not null and temperature_observed_at is not null
      and temperature_c between -80 and 60
      and isfinite(temperature_observed_at)
      and temperature_observed_at between ended_at - interval '2 hours' and ended_at + interval '15 minutes')
  );

create function runspot_private.save_my_run_with_temperature(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb,
  temperature_c double precision, temperature_observed_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  saved public.runs;
  summary jsonb;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode='42501';
  end if;
  if (temperature_c is null) <> (temperature_observed_at is null)
    or (temperature_c is not null and (
      temperature_c not between -80 and 60 or not isfinite(temperature_observed_at)
      or temperature_observed_at < end_time - interval '2 hours'
      or temperature_observed_at > end_time + interval '15 minutes'
    )) then
    raise exception '종료 시점의 기온 관측 자료가 올바르지 않습니다.' using errcode='22023';
  end if;
  if client_id is null or start_time is null or end_time is null
    or not isfinite(start_time) or not isfinite(end_time)
    or end_time <= start_time or end_time > now() + interval '5 minutes'
    or end_time - start_time > interval '7 days'
    or distance_metres is null or distance_metres < 0 or distance_metres > 1000000
    or active_seconds is null or active_seconds < 0
    or active_seconds > extract(epoch from end_time - start_time) + 1 then
    raise exception '러닝 기록의 거리, 시간 또는 날짜가 올바르지 않습니다.' using errcode='22023';
  end if;

  -- 최초 삽입에 기온도 포함해 동시 재시도에서 다른 기온으로 덮어쓰지 못하게 합니다.
  insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,
    temperature_c,temperature_observed_at)
  values(owner_id,client_id,start_time,end_time,distance_metres,active_seconds,
    temperature_c,temperature_observed_at)
  on conflict(user_id,client_run_id) do nothing;
  select * into strict saved from public.runs r
    where r.user_id=owner_id and r.client_run_id=client_id for update;
  if saved.temperature_c is distinct from temperature_c
    or saved.temperature_observed_at is distinct from temperature_observed_at then
    raise exception '이미 저장된 기온과 재시도 내용이 다릅니다.' using errcode='22023';
  end if;
  -- 거리·시간·경로 검증 실패 시 기온을 포함한 최초 삽입도 함께 취소됩니다.
  summary := runspot_private.save_my_run_with_route(
    client_id,start_time,end_time,distance_metres,active_seconds,route_segments);
  return summary || jsonb_build_object('temperature_c',saved.temperature_c,
    'temperature_observed_at',saved.temperature_observed_at);
end;
$$;

create function public.save_my_run_with_temperature(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb,
  temperature_c double precision, temperature_observed_at timestamptz
)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.save_my_run_with_temperature(client_id,start_time,end_time,
    distance_metres,active_seconds,route_segments,temperature_c,temperature_observed_at);
$$;
revoke all on function public.save_my_run_with_temperature(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz),
  runspot_private.save_my_run_with_temperature(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz)
  from public,anon,authenticated;
grant execute on function public.save_my_run_with_temperature(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz),
  runspot_private.save_my_run_with_temperature(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz)
  to authenticated;
notify pgrst, 'reload schema';
