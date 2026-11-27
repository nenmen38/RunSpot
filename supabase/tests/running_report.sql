\set ON_ERROR_STOP on
begin;
create function pg_temp.check_rr(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000d81','rr81@example.com',now()),
  ('00000000-0000-0000-0000-000000000d82','rr82@example.com',now());
-- 한국 시간 기준: 2026-03-02(월) 07시, 2026-03-15(일) 19시, 2026-11-10 07시, 2025-12-31 23시(지난해), 숨긴 기록 1개.
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status,hidden) values
  ('00000000-0000-0000-0000-00000000d801','00000000-0000-0000-0000-000000000d81',gen_random_uuid(),
    '2026-03-01 21:30+00','2026-03-01 22:00+00',5000,1500,'verified',false),
  ('00000000-0000-0000-0000-00000000d802','00000000-0000-0000-0000-000000000d81',gen_random_uuid(),
    '2026-03-15 09:00+00','2026-03-15 10:00+00',10000,3300,'verified',false),
  ('00000000-0000-0000-0000-00000000d803','00000000-0000-0000-0000-000000000d81',gen_random_uuid(),
    '2026-11-09 21:40+00','2026-11-09 22:00+00',3000,1080,'verified',false),
  ('00000000-0000-0000-0000-00000000d804','00000000-0000-0000-0000-000000000d81',gen_random_uuid(),
    '2025-12-31 13:30+00','2025-12-31 14:00+00',4000,1400,'verified',false),
  ('00000000-0000-0000-0000-00000000d805','00000000-0000-0000-0000-000000000d81',gen_random_uuid(),
    '2026-05-01 00:00+00','2026-05-01 01:00+00',20000,3500,'verified',true),
  ('00000000-0000-0000-0000-00000000d806','00000000-0000-0000-0000-000000000d82',gen_random_uuid(),
    '2026-03-15 09:00+00','2026-03-15 10:00+00',9000,3300,'verified',false);
insert into runspot_private.running_groups(id,host_id,state) values
  ('00000000-0000-0000-0000-00000000d8a1','00000000-0000-0000-0000-000000000d81','finished');
insert into runspot_private.running_group_members(group_id,user_id,status,run_id) values
  ('00000000-0000-0000-0000-00000000d8a1','00000000-0000-0000-0000-000000000d81','finished','00000000-0000-0000-0000-00000000d802'),
  ('00000000-0000-0000-0000-00000000d8a1','00000000-0000-0000-0000-000000000d82','finished','00000000-0000-0000-0000-00000000d806');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000d81',true);
select public.my_running_report('year','2026-07-01') as y \gset
select pg_temp.check_rr((:'y'::jsonb->>'starts')='2026-01-01','연초부터');
select pg_temp.check_rr((:'y'::jsonb->>'runs')::int=3 and (:'y'::jsonb->>'distance_m')::int=18000,'올해 3회 18km(숨김·지난해 제외)');
select pg_temp.check_rr((:'y'::jsonb->>'active_days')::int=3,'달린 날 3일');
select pg_temp.check_rr((:'y'::jsonb->>'previous_distance_m')::int=4000,'지난해 4km');
select pg_temp.check_rr((:'y'::jsonb->'longest'->>'distance_m')::int=10000,'최장 10km');
select pg_temp.check_rr((:'y'::jsonb->>'fastest_pace_sec')::int=300,'최고 페이스 5분/km');
select pg_temp.check_rr(:'y'::jsonb->'buckets'->2='15000'::jsonb and :'y'::jsonb->'buckets'->10='3000'::jsonb
  and jsonb_array_length(:'y'::jsonb->'buckets')=12,'달마다 거리');
select pg_temp.check_rr((:'y'::jsonb->>'favorite_time')='morning','아침 러너');
select pg_temp.check_rr((:'y'::jsonb->>'companions')::int=1,'함께 달린 러너 1명');
select public.my_running_report('month','2026-03-20') as m \gset
select pg_temp.check_rr((:'m'::jsonb->>'runs')::int=2 and jsonb_array_length(:'m'::jsonb->'buckets')=5
  and :'m'::jsonb->'buckets'->0='5000'::jsonb and :'m'::jsonb->'buckets'->2='10000'::jsonb,'3월 주차별 거리');
select pg_temp.check_rr((:'m'::jsonb->>'favorite_weekday')::int in (1,7),'요일');
select pg_temp.check_rr(pg_temp.fails($q$select public.my_running_report('week','2026-03-01')$q$,'22023'),'기간 확인');
reset role;
set local role anon;
select pg_temp.check_rr(pg_temp.fails($q$select public.my_running_report('year','2026-01-01')$q$,'42501'),'로그인 필요');
rollback;
