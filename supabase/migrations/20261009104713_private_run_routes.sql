-- 측정 경로는 공개 기록과 분리하며 직접 조회·변경 권한을 주지 않습니다.
create table runspot_private.measured_run_routes (
  run_id uuid primary key references public.runs(id) on delete cascade,
  segments jsonb not null check (jsonb_typeof(segments)='array'),
  sample_count integer not null check (sample_count between 0 and 500000)
);
alter table runspot_private.measured_run_routes enable row level security;
revoke all on runspot_private.measured_run_routes from public, anon, authenticated;
grant select, insert, update, delete on runspot_private.measured_run_routes to service_role;

create function runspot_private.save_my_run_with_route(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  summary jsonb;
  saved_run_id uuid;
  segment jsonb;
  point jsonb;
  samples integer := 0;
  existing jsonb;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode='42501';
  end if;
  if route_segments is null or jsonb_typeof(route_segments)<>'array' then
    raise exception '경로 구간이 올바르지 않습니다.' using errcode='22023';
  end if;
  if jsonb_array_length(route_segments)>50000 or octet_length(route_segments::text)>33554432 then
    raise exception '경로 데이터가 너무 큽니다.' using errcode='22023';
  end if;
  for segment in select value from jsonb_array_elements(route_segments) loop
    if jsonb_typeof(segment)<>'array' then
      raise exception '경로 구간이 올바르지 않습니다.' using errcode='22023';
    end if;
    if jsonb_array_length(segment)=0 then
      raise exception '빈 경로 구간은 저장할 수 없습니다.' using errcode='22023';
    end if;
    samples := samples + jsonb_array_length(segment);
    if samples>500000 then
      raise exception '경로 좌표가 너무 많습니다.' using errcode='22023';
    end if;
    for point in select value from jsonb_array_elements(segment) loop
      if jsonb_typeof(point)<>'array' then
        raise exception '경로 좌표가 올바르지 않습니다.' using errcode='22023';
      end if;
      if jsonb_array_length(point)<>2 or jsonb_typeof(point->0)<>'number'
        or jsonb_typeof(point->1)<>'number' then
        raise exception '경로 좌표가 올바르지 않습니다.' using errcode='22023';
      end if;
      if (point->>0)::numeric not between -90 and 90
        or (point->>1)::numeric not between -180 and 180 then
        raise exception '경로 좌표의 범위가 올바르지 않습니다.' using errcode='22023';
      end if;
    end loop;
  end loop;

  -- 기존 측정값 검증을 재사용하고 경로까지 같은 트랜잭션에서 확정합니다.
  summary := public.save_my_run(client_id,start_time,end_time,distance_metres,active_seconds);
  select r.id into strict saved_run_id from public.runs r
    where r.user_id=owner_id and r.client_run_id=client_id for update;
  insert into runspot_private.measured_run_routes(run_id,segments,sample_count)
    values(saved_run_id,route_segments,samples) on conflict do nothing;
  select t.segments into strict existing from runspot_private.measured_run_routes t where t.run_id=saved_run_id;
  if existing<>route_segments then
    raise exception '이미 저장된 경로와 재시도 내용이 다릅니다.' using errcode='22023';
  end if;
  return summary;
end;
$$;

create function runspot_private.my_run_route(requested_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  result jsonb;
begin
  if owner_id is null or not runspot_private.is_active(owner_id)
    or not exists(select 1 from public.runs r where r.id=requested_run_id and r.user_id=owner_id) then
    raise exception '이 기록을 조회할 수 없습니다.' using errcode='42501';
  end if;
  select segments into result from runspot_private.measured_run_routes where run_id=requested_run_id;
  return coalesce(result,'[]'::jsonb);
end;
$$;

revoke all on function runspot_private.save_my_run_with_route(uuid,timestamptz,timestamptz,integer,integer,jsonb),
  runspot_private.my_run_route(uuid) from public,anon,authenticated;
grant execute on function runspot_private.save_my_run_with_route(uuid,timestamptz,timestamptz,integer,integer,jsonb),
  runspot_private.my_run_route(uuid) to authenticated;

create function public.save_my_run_with_route(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb
)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.save_my_run_with_route(client_id,start_time,end_time,distance_metres,active_seconds,route_segments);
$$;
create function public.my_run_route(requested_run_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_run_route(requested_run_id);
$$;
revoke all on function public.save_my_run_with_route(uuid,timestamptz,timestamptz,integer,integer,jsonb),
  public.my_run_route(uuid) from public,anon,authenticated;
grant execute on function public.save_my_run_with_route(uuid,timestamptz,timestamptz,integer,integer,jsonb),
  public.my_run_route(uuid) to authenticated;
notify pgrst, 'reload schema';
