\set ON_ERROR_STOP on
begin;
create function pg_temp.check_course(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000c51','course51@example.com',now()),
 ('00000000-0000-0000-0000-000000000c52','course52@example.com',now());
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status) values
 ('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-000000000c51',gen_random_uuid(),now()-interval '1 hour',now()-interval '20 minutes',5200,2000,'verified'),
 ('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-000000000c51',gen_random_uuid(),now()-interval '3 hours',now()-interval '2 hours',3000,2000,'verified');
-- 1000개 점(두 구간)을 가진 경로입니다.
insert into runspot_private.measured_run_routes(run_id,segments,sample_count)
select '00000000-0000-0000-0000-00000000c501',
  jsonb_build_array(
    (select jsonb_agg(jsonb_build_array(37.5+i*0.00001,127.0) order by i) from generate_series(1,600) i),
    (select jsonb_agg(jsonb_build_array(37.6,127.0+i*0.00001) order by i) from generate_series(1,400) i)),
  1000;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000c51',true);
select public.save_course('00000000-0000-0000-0000-00000000c501','  한강 5km  ') as c \gset
select pg_temp.check_course(:'c'::jsonb->>'name'='한강 5km' and (:'c'::jsonb->>'distance_m')::int=5200,'코스 저장');
select pg_temp.check_course(jsonb_array_length(:'c'::jsonb->'segments')=2,'구간 유지');
select pg_temp.check_course((select sum(jsonb_array_length(s)) from jsonb_array_elements(:'c'::jsonb->'segments') s) between 300 and 420,'점 줄이기');
select pg_temp.check_course(:'c'::jsonb->'segments'->0->-1='[37.506,127.0]'::jsonb,'구간 끝점 유지');
select pg_temp.check_course(pg_temp.fails($q$select public.save_course('00000000-0000-0000-0000-00000000c502','경로없음')$q$,'P0001'),'경로 없는 기록 거절');
select pg_temp.check_course(pg_temp.fails($q$select public.save_course('00000000-0000-0000-0000-00000000c501','')$q$,'22023'),'빈 이름 거절');
select pg_temp.check_course(jsonb_array_length(public.my_courses())=1,'내 코스 목록');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000c52',true);
select pg_temp.check_course(pg_temp.fails($q$select public.save_course('00000000-0000-0000-0000-00000000c501','남의 기록')$q$,'P0001'),'남의 기록 거절');
select pg_temp.check_course(jsonb_array_length(public.my_courses())=0,'남의 코스 안 보임');
select public.delete_course((:'c'::jsonb->>'id')::uuid);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000c51',true);
select pg_temp.check_course(jsonb_array_length(public.my_courses())=1,'남이 못 지움');
select public.delete_course((:'c'::jsonb->>'id')::uuid);
select pg_temp.check_course(jsonb_array_length(public.my_courses())=0,'코스 지우기');
rollback;
