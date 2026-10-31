-- 분석 시각·고도·GPS 품질은 비공개로 보존하고 본인 전용 함수만 제공합니다.
create table runspot_private.run_analysis_data (
  run_id uuid primary key references public.runs(id) on delete cascade,
  data jsonb not null
);
alter table runspot_private.run_analysis_data enable row level security;
create policy run_analysis_no_direct_access on runspot_private.run_analysis_data
  for all to authenticated using (false) with check (false);
revoke all on runspot_private.run_analysis_data from public,anon,authenticated;

create function runspot_private.valid_run_analysis(data jsonb,distance_m integer,active_sec integer,elapsed_ms numeric)
returns boolean language plpgsql immutable set search_path='' as $$
declare k text; r jsonb; n jsonb; a numeric[]; width integer; limit_rows integer;
 last_wall numeric:=0; last_active numeric:=0; last_distance numeric:=0; last_pause numeric:=0; last_km numeric:=0; window_cursor integer:=0;
begin
 if data is null or jsonb_typeof(data) is distinct from 'object' or data->>'version' is distinct from '1'
   or (select count(*) from jsonb_object_keys(data))<>5 or pg_column_size(data)>16000000 then return false; end if;
 foreach k in array array['windows','pauses','elevation','gps'] loop
  width:=case k when 'windows' then 4 when 'pauses' then 3 when 'elevation' then 4 else 8 end;
  limit_rows:=case k when 'elevation' then 100000 when 'gps' then 1001 else 10000 end;
  if jsonb_typeof(data->k) is distinct from 'array' or jsonb_array_length(data->k)>limit_rows then return false; end if;
  for r in select value from jsonb_array_elements(data->k) loop
   if jsonb_typeof(r)<>'array' or jsonb_array_length(r)<>width then return false; end if;
   a:=array[]::numeric[];
   for n in select value from jsonb_array_elements(r) loop
    if jsonb_typeof(n)<>'number' or abs(n::text::numeric)>1e12 then return false; end if;
    a:=array_append(a,n::text::numeric);
   end loop;
   if k='windows' then
    if a[1]<last_wall or a[2]<a[1] or a[2]>elapsed_ms+1000 or a[3]<>last_active or a[4]<a[3]
      or a[4]-a[3]>a[2]-a[1]+1000 or a[4]>(active_sec+1)*1000 then return false; end if;
    last_wall:=a[2]; last_active:=a[4];
   elsif k='pauses' then
    if a[1]<last_pause or a[2]<a[1] or a[2]>elapsed_ms+1000 or a[3] not in (0,1,2,3) then return false; end if;
    while window_cursor<jsonb_array_length(data->'windows') and (data->'windows'->window_cursor->>1)::numeric<=a[1] loop
      window_cursor:=window_cursor+1;
    end loop;
    if window_cursor<jsonb_array_length(data->'windows') and (data->'windows'->window_cursor->>0)::numeric<a[2]
      and (data->'windows'->window_cursor->>1)::numeric>a[1] then return false; end if;
    last_pause:=a[2];
   elsif k='elevation' then
    if a[1]<last_distance or a[2]<=a[1] or a[2]>distance_m+1 or abs(a[3])>20000 or a[4]<=0 or a[4]>20 then return false; end if;
    last_distance:=a[2];
   else
    if a[1]<>trunc(a[1]) or a[1]<=last_km or a[1]>1001 or a[2]<0 or a[2]<>trunc(a[2]) or a[3]<0 or a[3]>a[2]
      or a[3]<>trunc(a[3]) or a[4]<0 or a[4]<>trunc(a[4]) or a[5]<0 or a[5]>elapsed_ms+1000 or a[6]<0 or a[7]<0 or a[8]<0 or a[8]>a[2] or a[8]<>trunc(a[8]) then return false; end if;
    last_km:=a[1];
   end if;
  end loop;
 end loop;
 return abs(last_active-active_sec*1000)<1001;
exception when others then return false;
end;
$$;
revoke all on function runspot_private.valid_run_analysis(jsonb,integer,integer,numeric) from public,anon,authenticated;

create function runspot_private.save_my_run_with_analysis(
 client_id uuid,start_time timestamptz,end_time timestamptz,distance_metres integer,active_seconds integer,
 route_segments jsonb,temperature_c double precision,temperature_observed_at timestamptz,split_data jsonb,motion_samples jsonb,analysis_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); result jsonb; existing jsonb; saved_id uuid;
begin
 if owner_id is null or not runspot_private.is_active(owner_id) then raise exception '로그인 상태를 확인해 주세요.' using errcode='42501'; end if;
 if start_time is null or end_time is null or not isfinite(start_time) or not isfinite(end_time)
   or distance_metres is null or active_seconds is null
   or not runspot_private.valid_run_analysis(analysis_data,distance_metres,active_seconds,extract(epoch from end_time-start_time)*1000) then
   raise exception '러닝 분석 자료가 올바르지 않습니다.' using errcode='22023';
 end if;
 result:=runspot_private.save_my_run_with_motion(client_id,start_time,end_time,distance_metres,active_seconds,
   route_segments,temperature_c,temperature_observed_at,split_data,motion_samples);
 saved_id:=(result->>'id')::uuid;
 insert into runspot_private.run_analysis_data(run_id,data) values(saved_id,analysis_data) on conflict do nothing;
 select data into strict existing from runspot_private.run_analysis_data where run_id=saved_id;
 if existing is distinct from analysis_data then raise exception '이미 저장된 분석 자료와 다릅니다.' using errcode='22023'; end if;
 return result;
end;
$$;
create function public.save_my_run_with_analysis(
 client_id uuid,start_time timestamptz,end_time timestamptz,distance_metres integer,active_seconds integer,
 route_segments jsonb,temperature_c double precision,temperature_observed_at timestamptz,split_data jsonb,motion_samples jsonb,analysis_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select runspot_private.save_my_run_with_analysis(client_id,start_time,end_time,distance_metres,active_seconds,
 route_segments,temperature_c,temperature_observed_at,split_data,motion_samples,analysis_data);
$$;
revoke all on function public.save_my_run_with_analysis(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb,jsonb),
 runspot_private.save_my_run_with_analysis(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.save_my_run_with_analysis(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb,jsonb),
 runspot_private.save_my_run_with_analysis(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb,jsonb) to authenticated;

create function runspot_private.my_run_analysis(requested_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); r public.runs; analysis jsonb;
begin
 if owner_id is null or not runspot_private.is_active(owner_id) then raise exception '로그인 상태를 확인해 주세요.' using errcode='42501'; end if;
 select * into r from public.runs where id=requested_run_id and user_id=owner_id;
 if not found then raise exception '기록을 조회할 수 없습니다.' using errcode='42501'; end if;
 select data into analysis from runspot_private.run_analysis_data where run_id=r.id;
 return jsonb_build_object('started_at',r.started_at,'ended_at',r.ended_at,'distance_m',r.distance_m,'duration_sec',r.duration_sec,
   'split_data',r.split_data,'temperature_c',r.temperature_c,'temperature_observed_at',r.temperature_observed_at,'analysis_data',analysis);
end;
$$;
create function public.my_run_analysis(requested_run_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$ select runspot_private.my_run_analysis(requested_run_id); $$;
revoke all on function public.my_run_analysis(uuid),runspot_private.my_run_analysis(uuid) from public,anon,authenticated;
grant execute on function public.my_run_analysis(uuid),runspot_private.my_run_analysis(uuid) to authenticated;
