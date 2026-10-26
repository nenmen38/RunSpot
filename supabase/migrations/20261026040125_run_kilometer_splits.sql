-- 구간 기록은 본인 기록의 기존 조회 정책을 따르며 이전 기록은 빈 값으로 유지합니다.
alter table public.runs add column split_data jsonb;

create function runspot_private.valid_run_splits(data jsonb, metres integer, seconds integer)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  item jsonb;
  count_items integer;
  ordinal integer := 0;
  distance_value numeric;
  time_value numeric;
  total_distance numeric := 0;
  total_time numeric := 0;
begin
  if data is null then return true; end if;
  if jsonb_typeof(data) <> 'array' or octet_length(data::text) > 131072 then return false; end if;
  count_items := jsonb_array_length(data);
  if count_items > 1001 then return false; end if;
  if count_items = 0 then return metres = 0; end if;
  for item in select value from jsonb_array_elements(data) loop
    ordinal := ordinal + 1;
    if jsonb_typeof(item) <> 'object'
      or jsonb_typeof(item->'distance_m') is distinct from 'number'
      or jsonb_typeof(item->'duration_us') is distinct from 'number'
      or (select count(*) from jsonb_object_keys(item)) <> 2 then return false; end if;
    distance_value := (item->>'distance_m')::numeric;
    time_value := (item->>'duration_us')::numeric;
    if distance_value <= 0 or distance_value > 1000
      or (ordinal < count_items and distance_value <> 1000)
      or time_value < 0 or time_value > 604800000000
      or time_value <> trunc(time_value) then return false; end if;
    total_distance := total_distance + distance_value;
    total_time := total_time + time_value;
  end loop;
  -- 앱은 정수 거리와 버림한 활동 시간을 전송하므로 해당 반올림 범위만 허용합니다.
  return abs(total_distance - metres) <= 0.500001
    and total_time >= seconds::numeric * 1000000
    and total_time < (seconds::numeric + 1) * 1000000;
end;
$$;
revoke all on function runspot_private.valid_run_splits(jsonb,integer,integer) from public,anon,authenticated;
alter table public.runs add constraint runs_split_data_check
  check (runspot_private.valid_run_splits(split_data,distance_m,duration_sec));

create function runspot_private.save_my_run_with_splits(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb,
  temperature_c double precision, temperature_observed_at timestamptz, split_data jsonb
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
  if client_id is null or start_time is null or end_time is null
    or not isfinite(start_time) or not isfinite(end_time)
    or end_time <= start_time or end_time > now() + interval '5 minutes'
    or end_time - start_time > interval '7 days'
    or distance_metres is null or distance_metres < 0 or distance_metres > 1000000
    or active_seconds is null or active_seconds < 0
    or active_seconds > extract(epoch from end_time - start_time) + 1
    or not runspot_private.valid_run_splits(split_data,distance_metres,active_seconds) then
    raise exception '러닝 기록의 구간·거리·시간 또는 날짜가 올바르지 않습니다.' using errcode='22023';
  end if;
  -- 구간과 기온을 최초 삽입에 포함해 재전송 및 동시 요청의 값을 고정합니다.
  insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,
    temperature_c,temperature_observed_at,split_data)
  values(owner_id,client_id,start_time,end_time,distance_metres,active_seconds,
    temperature_c,temperature_observed_at,split_data)
  on conflict(user_id,client_run_id) do nothing;
  select * into strict saved from public.runs r
    where r.user_id=owner_id and r.client_run_id=client_id for update;
  if saved.split_data is distinct from split_data then
    raise exception '이미 저장된 구간 기록과 재시도 내용이 다릅니다.' using errcode='22023';
  end if;
  -- 기존 날짜·기온·경로 검사가 실패하면 구간 기록 삽입도 함께 취소됩니다.
  summary := runspot_private.save_my_run_with_temperature(client_id,start_time,end_time,
    distance_metres,active_seconds,route_segments,temperature_c,temperature_observed_at);
  return summary || jsonb_build_object('split_data',saved.split_data);
end;
$$;

create function public.save_my_run_with_splits(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb,
  temperature_c double precision, temperature_observed_at timestamptz, split_data jsonb
)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.save_my_run_with_splits(client_id,start_time,end_time,
    distance_metres,active_seconds,route_segments,temperature_c,temperature_observed_at,split_data);
$$;
revoke all on function public.save_my_run_with_splits(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb),
  runspot_private.save_my_run_with_splits(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function public.save_my_run_with_splits(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb),
  runspot_private.save_my_run_with_splits(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb)
  to authenticated;
notify pgrst, 'reload schema';
