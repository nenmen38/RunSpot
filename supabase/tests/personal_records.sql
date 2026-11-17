\set ON_ERROR_STOP on
begin;
create function pg_temp.check_pb(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
create function pg_temp.splits(variadic seconds integer[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('distance_m',1000,'duration_us',s::bigint*1000000)) from unnest(seconds) s;
$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000291','pb291@example.com',now()),
 ('00000000-0000-0000-0000-000000000292','pb292@example.com',now());
update public.profiles set nickname='기록검증'||right(id::text,3) where id::text like '%00000000029_';
-- 5km(300+290+310+305+295=1500초), 2km(280+320초), 반려된 1km(200초)
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,split_data,integrity_status) values
 ('00000000-0000-0000-0000-000000000291',gen_random_uuid(),now()-interval '3 days',now()-interval '3 days'+interval '1500 seconds',
   5000,1500,pg_temp.splits(300,290,310,305,295),'pending'),
 ('00000000-0000-0000-0000-000000000291','00000000-0000-0000-0000-0000000002b2',now()-interval '1 day',now()-interval '1 day'+interval '600 seconds',
   2000,600,pg_temp.splits(280,320),'verified'),
 ('00000000-0000-0000-0000-000000000291',gen_random_uuid(),now()-interval '2 hours',now()-interval '2 hours'+interval '200 seconds',
   1000,200,pg_temp.splits(200),'rejected'),
 ('00000000-0000-0000-0000-000000000292',gen_random_uuid(),now()-interval '1 hour',now()-interval '1 hour'+interval '150 seconds',
   1000,150,pg_temp.splits(150),'verified');
select id as fast_run from public.runs where client_run_id='00000000-0000-0000-0000-0000000002b2' \gset

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000291',true);
select public.my_personal_records() as records \gset
select pg_temp.check_pb(jsonb_array_length(:'records'::jsonb)=2,'1km·5km만 있음(10km 없음)');
select pg_temp.check_pb((:'records'::jsonb->0->>'distance_km')::int=1
  and (:'records'::jsonb->0->>'duration_us')::bigint=280000000
  and :'records'::jsonb->0->>'run_id'=:'fast_run','1km 최고는 반려 기록·남의 기록 제외');
select pg_temp.check_pb((:'records'::jsonb->1->>'distance_km')::int=5
  and (:'records'::jsonb->1->>'duration_us')::bigint=1500000000,'5km 최고');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000293',true);
select pg_temp.check_pb(pg_temp.fails('select public.my_personal_records()','42501'),'없는 계정 거부');
reset role;
set local role anon;
select pg_temp.check_pb(pg_temp.fails('select public.my_personal_records()','42501'),'익명 거부');
rollback;
