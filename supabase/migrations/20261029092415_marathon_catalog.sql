-- 외부 대회는 사용자 게시글과 분리해 보관하며 일반 계정에는 읽기 RPC만 제공합니다.
create table runspot_private.marathon_catalog (
 id text primary key check(length(id) between 1 and 200),
 event_date date not null,
 data jsonb not null check(jsonb_typeof(data)='object'),
 available boolean not null default true,
 synced_at timestamptz not null default now()
);
create index marathon_catalog_date on runspot_private.marathon_catalog(event_date,id) where available;
create table runspot_private.marathon_sync_state (
 singleton boolean primary key default true check(singleton),
 synced_at timestamptz,
 attempted_at timestamptz,
 last_error text
);
insert into runspot_private.marathon_sync_state(singleton) values(true);
alter table runspot_private.marathon_catalog enable row level security;
alter table runspot_private.marathon_sync_state enable row level security;
revoke all on runspot_private.marathon_catalog,runspot_private.marathon_sync_state from public,anon,authenticated;
grant all on runspot_private.marathon_catalog,runspot_private.marathon_sync_state to service_role;
create policy marathon_catalog_service on runspot_private.marathon_catalog to service_role using(true) with check(true);
create policy marathon_sync_service on runspot_private.marathon_sync_state to service_role using(true) with check(true);

-- 공식 접수 마감과 날짜 만료를 우선하며, 날짜·상태가 모두 없으면 추정하지 않습니다.
create function runspot_private.marathon_status(registration jsonb,event_date date,at_time timestamptz default now())
returns text language plpgsql stable set search_path='' as $$
declare
 state text := regexp_replace(coalesce(registration->>'status',''),'[[:space:]]','','g');
 starts timestamptz;
 ends timestamptz;
begin
 if registration->>'startDate' ~ '^\d{4}-\d{2}-\d{2}$' then
  starts := ((registration->>'startDate')||' '||coalesce(nullif(registration->>'startTime',''),'00:00'))::timestamp at time zone 'Asia/Seoul';
 end if;
 if registration->>'endDate' ~ '^\d{4}-\d{2}-\d{2}$' then
  ends := ((registration->>'endDate')||' '||coalesce(nullif(registration->>'endTime',''),'23:59:59.999999'))::timestamp at time zone 'Asia/Seoul';
 end if;
 if state in ('접수마감','모집완료','마감','마감완료','모집마감','closed')
   or (at_time at time zone 'Asia/Seoul')::date > event_date
   or (ends is not null and at_time > ends) then return 'closed'; end if;
 if starts is not null and at_time < starts then return 'upcoming'; end if;
 if state in ('접수중','모집중','open') then return 'open'; end if;
 if starts is not null and ends is not null and at_time between starts and ends then return 'open'; end if;
 if state in ('접수대기','접수예정','모집예정','예정','upcoming') then return 'upcoming'; end if;
 return 'unknown';
end;
$$;

-- 완전한 목록만 원자적으로 반영합니다. 중복·잘못된 날짜·부분 응답이면 이전 자료를 유지합니다.
create function runspot_private.import_marathons(payload jsonb)
returns integer language plpgsql set search_path='' as $$
declare item jsonb; event_day date; total integer; stamp timestamptz:=clock_timestamp(); ids text[]:='{}';
begin
 perform pg_advisory_xact_lock(hashtextextended('marathon_catalog',0));
 if payload->'success' is distinct from 'true'::jsonb or jsonb_typeof(payload->'data') is distinct from 'array'
  or payload#>>'{meta,nextCursor}' is not null then raise exception '불완전한 마라톤 응답입니다.'; end if;
 total:=jsonb_array_length(payload->'data');
 if total not between 1 and 5000 or (payload->>'count')::integer is distinct from total then
  raise exception '마라톤 응답 개수가 올바르지 않습니다.'; end if;
 for item in select value from jsonb_array_elements(payload->'data') loop
  if jsonb_typeof(item) is distinct from 'object'
   or jsonb_typeof(item->'id') is distinct from 'string'
   or jsonb_typeof(item->'name') is distinct from 'string' or length(coalesce(item->>'id','')) not between 1 and 200
   or (item->>'id')=any(ids) or length(btrim(coalesce(item->>'name',''))) not between 1 and 200
   or coalesce(item#>>'{event,startDate}','') !~ '^\d{4}-\d{2}-\d{2}$'
   or jsonb_typeof(item->'event') is distinct from 'object'
   or (item->'registration' is not null and jsonb_typeof(item->'registration') not in ('object','null')) then
   raise exception '마라톤 항목이 올바르지 않습니다.'; end if;
  if exists(select 1 from jsonb_each(item) e where e.key in ('location','hosts','info') and jsonb_typeof(e.value) not in ('object','null'))
   or (item#>'{registration,price}' is not null and jsonb_typeof(item#>'{registration,price}') not in ('object','null')) then
   raise exception '마라톤 부가 정보가 올바르지 않습니다.'; end if;
  event_day:=(item#>>'{event,startDate}')::date;
  -- 날짜와 시간을 여기서 검증해 목록 조회 중 하나의 잘못된 값 때문에 전체가 실패하지 않게 합니다.
  perform runspot_private.marathon_status(item->'registration',event_day);
  ids:=array_append(ids,item->>'id');
  insert into runspot_private.marathon_catalog(id,event_date,data,available,synced_at)
   values(item->>'id',event_day,item,true,stamp)
   on conflict(id) do update set event_date=excluded.event_date,data=excluded.data,available=true,synced_at=stamp;
 end loop;
 update runspot_private.marathon_catalog set available=false where not(id=any(ids));
 update runspot_private.marathon_sync_state set synced_at=stamp,attempted_at=stamp,last_error=null where singleton;
 return total;
end;
$$;

create function runspot_private.marathon_events()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform runspot_private.require_board_viewer();
 return jsonb_build_object('synced_at',(select synced_at from runspot_private.marathon_sync_state where singleton),
  'events',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'data',m.data,
   'status',runspot_private.marathon_status(m.data->'registration',m.event_date)) order by m.event_date,m.id),'[]'::jsonb)
   from runspot_private.marathon_catalog m where available and event_date >= (now() at time zone 'Asia/Seoul')::date));
end;
$$;
create function public.marathon_events()
returns jsonb language sql stable security invoker set search_path='' as $$ select runspot_private.marathon_events(); $$;
revoke all on function runspot_private.marathon_status(jsonb,date,timestamptz),runspot_private.import_marathons(jsonb),
 runspot_private.marathon_events(),public.marathon_events() from public,anon,authenticated;
grant execute on function runspot_private.import_marathons(jsonb),runspot_private.marathon_status(jsonb,date,timestamptz) to service_role;
grant execute on function runspot_private.marathon_events(),public.marathon_events() to authenticated;
notify pgrst,'reload schema';
