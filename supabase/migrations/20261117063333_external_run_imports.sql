-- 외부 기록은 측정 증거가 없어 개인 보관함에서만 사용하며 보상·순위 테이블과 분리합니다.
create table runspot_private.external_runs(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 source text not null check(source in ('file','appleHealth','googleHealthConnect')),
 source_id text not null check(length(source_id) between 1 and 300),
 started_at timestamptz not null,ended_at timestamptz not null,
 distance_m integer not null check(distance_m between 0 and 500000),duration_sec integer not null check(duration_sec between 1 and 604800),
 route jsonb not null default '[]',created_at timestamptz not null default now(),
 check(ended_at>started_at and ended_at<=started_at+interval '7 days'),unique(user_id,source,source_id)
);
create index external_runs_owner on runspot_private.external_runs(user_id,started_at desc,id);
alter table runspot_private.external_runs enable row level security;
revoke all on runspot_private.external_runs from public,anon,authenticated;
create function runspot_private.external_runs(operation text default 'list',payload jsonb default null,requested_id uuid default null,page_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); segment jsonb; point jsonb; total integer:=0;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 if operation='import' then
   if payload is null or octet_length(payload::text)>1000000 or jsonb_typeof(payload->'route')<>'array' then raise exception '가져올 기록 형식을 확인해 주세요.' using errcode='22023'; end if;
   for segment in select value from jsonb_array_elements(payload->'route') loop
     if jsonb_typeof(segment)<>'array' then raise exception '경로 형식 오류' using errcode='22023'; end if;
     for point in select value from jsonb_array_elements(segment) loop
       total:=total+1;
       if total>10000 or jsonb_typeof(point)<>'array' or jsonb_array_length(point)<>2 or jsonb_typeof(point->0)<>'number' or jsonb_typeof(point->1)<>'number' or abs((point->>0)::numeric)>90 or abs((point->>1)::numeric)>180 then raise exception '경로 좌표 오류' using errcode='22023'; end if;
     end loop;
   end loop;
   perform pg_advisory_xact_lock(hashtextextended('external_runs:'||viewer::text,0));
   if (select count(*) from runspot_private.external_runs where user_id=viewer)>=10000 then raise exception '외부 기록 보관 한도에 도달했습니다.' using errcode='22023'; end if;
   insert into runspot_private.external_runs(user_id,source,source_id,started_at,ended_at,distance_m,duration_sec,route)
   values(viewer,payload->>'source',payload->>'source_id',(payload->>'started_at')::timestamptz,(payload->>'ended_at')::timestamptz,(payload->>'distance_m')::integer,(payload->>'duration_sec')::integer,payload->'route')
   on conflict(user_id,source,source_id) do nothing;
 elsif operation='delete' then delete from runspot_private.external_runs where id=requested_id and user_id=viewer;
 elsif operation<>'list' or operation is null then raise exception '지원하지 않는 작업입니다.' using errcode='22023'; end if;
 if page_offset is null or page_offset<0 or page_offset>10000 then raise exception '페이지 오류' using errcode='22023'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at desc,x.id),'[]') from (
 select id,source,started_at,ended_at,distance_m,duration_sec from runspot_private.external_runs where user_id=viewer order by started_at desc,id limit 30 offset page_offset)x);
end;
$$;
create function public.external_runs(operation text default 'list',payload jsonb default null,requested_id uuid default null,page_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.external_runs(operation,payload,requested_id,page_offset); $$;
revoke all on function public.external_runs(text,jsonb,uuid,integer),runspot_private.external_runs(text,jsonb,uuid,integer) from public,anon,authenticated;
grant execute on function public.external_runs(text,jsonb,uuid,integer),runspot_private.external_runs(text,jsonb,uuid,integer) to authenticated;
notify pgrst,'reload schema';
