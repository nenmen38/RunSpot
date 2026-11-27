\set ON_ERROR_STOP on
begin;
create function pg_temp.check_st(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000e91','st91@example.com',now()),
 ('00000000-0000-0000-0000-000000000e92','st92@example.com',now()),
 ('00000000-0000-0000-0000-000000000e93','st93@example.com',now());
-- 이번 주 월요일(한국 시간) 정오 기준으로 주마다 기록을 만듭니다.
create temp table base as select (date_trunc('week', now() at time zone 'Asia/Seoul') + interval '12 hours') at time zone 'Asia/Seoul' as monday;
-- e91: 지난 3주 각 10km, 4주 전 2km(목표 미달), 이번 주 아직 0.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000e91',gen_random_uuid(),b.monday-(w*interval '7 days'),b.monday-(w*interval '7 days')+interval '1 hour',m,3500,'verified'
from base b, (values (1,10000),(2,10000),(3,10000),(4,2000)) v(w,m);
insert into runspot_private.weekly_goals(user_id,kilometers) values('00000000-0000-0000-0000-000000000e91',10);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000e91',true);
select public.my_running_streak() as s \gset
select pg_temp.check_st((:'s'::jsonb->>'weeks')::int=3 and (:'s'::jsonb->>'goal_based')::boolean
  and not (:'s'::jsonb->>'this_week_done')::boolean,'목표 3주 연속');
select pg_temp.check_st((:'s'::jsonb->>'goal_m')::int=10000,'목표 거리');
reset role;
-- 목표를 지우면 주 1회 이상 달린 주를 셉니다(4주 전 2km도 포함).
delete from runspot_private.weekly_goals where user_id='00000000-0000-0000-0000-000000000e91';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000e91',true);
select pg_temp.check_st((public.my_running_streak()->>'weeks')::int=4,'목표 없이 4주 연속');
reset role;

-- 응원 알림: 마지막 러닝이 3일 전인 e92(기기 있음)만, e93(기기 없음)은 빼고 만듭니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status) values
 ('00000000-0000-0000-0000-000000000e92',gen_random_uuid(),now()-interval '3 days 1 hour',now()-interval '3 days',3000,1800,'verified'),
 ('00000000-0000-0000-0000-000000000e93',gen_random_uuid(),now()-interval '3 days 1 hour',now()-interval '3 days',3000,1800,'verified');
insert into auth.sessions(id,user_id) values('00000000-0000-0000-0000-000000000e99','00000000-0000-0000-0000-000000000e92');
insert into runspot_private.push_devices(token,user_id,session_id,platform,registered_at)
 values(repeat('c',40),'00000000-0000-0000-0000-000000000e92','00000000-0000-0000-0000-000000000e99','android',now()-interval '1 day');
select pg_temp.check_st(runspot_private.enqueue_comeback_pushes()=1,'응원 알림 1건');
select pg_temp.check_st(runspot_private.enqueue_comeback_pushes()=0,'같은 날 두 번 만들지 않음');
select pg_temp.check_st((select runspot_private.push_text(j)->>'body' from runspot_private.push_jobs j where j.kind='comeback') like '러너가 운동화를%','3일째 문구');
select pg_temp.check_st((select runspot_private.push_allowed(j) from runspot_private.push_jobs j where j.kind='comeback'),'보낼 수 있음');
-- 설정에서 끄면 보내지 않습니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000e92',true);
select pg_temp.check_st(not (public.my_push_preferences(comeback=>false)->>'comeback')::boolean,'응원 알림 끄기');
reset role;
select pg_temp.check_st(not (select runspot_private.push_allowed(j) from runspot_private.push_jobs j where j.kind='comeback'),'끄면 안 보냄');
update runspot_private.push_preferences set comeback=true where user_id='00000000-0000-0000-0000-000000000e92';
-- 그사이 달렸으면 보내지 않습니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status) values
 ('00000000-0000-0000-0000-000000000e92',gen_random_uuid(),now()-interval '40 minutes',now()-interval '10 minutes',3000,1800,'verified');
select pg_temp.check_st(not (select runspot_private.push_allowed(j) from runspot_private.push_jobs j where j.kind='comeback'),'달렸으면 안 보냄');
rollback;
