\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000081','achievement81@example.com',now()),
 ('00000000-0000-0000-0000-000000000082','review82@example.com',now()),
 ('00000000-0000-0000-0000-000000000083','other83@example.com',now());
update public.profiles set nickname='검증'||right(id::text,2) where id::text like '%00000000008_';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000082','moderator');
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
select '00000000-0000-0000-0000-000000000081',gen_random_uuid(),now()-interval '1 day'-i*interval '1 hour',
 now()-interval '1 day'-i*interval '1 hour'+interval '30 minutes',5000,1800 from generate_series(1,10) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true(jsonb_array_length(public.my_achievements())=3,'실제 업적 세 개');
select pg_temp.assert_true((select bool_and((e->>'achieved_at') is not null) from jsonb_array_elements(public.my_achievements())e),'누적 10회·50km 달성');
select pg_temp.assert_true(pg_temp.fails('select public.review_cases()','42501'),'일반 사용자 관리자 조회 거부');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true(pg_temp.fails('select public.review_cases()','42501'),'다중 인증만으로 관리자 권한 획득 불가');
reset role;
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
 values('00000000-0000-0000-0000-000000000081',gen_random_uuid(),now()-interval '1 hour',now()-interval '50 minutes',6000,600)
 returning id as suspicious_run \gset
select id as review_id from runspot_private.integrity_cases where run_id=:'suspicious_run' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
select pg_temp.assert_true(pg_temp.fails('select public.review_cases()','42501'),'관리자도 다중 인증 필요');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true(jsonb_array_length(public.review_cases())>=1,'다중 인증 관리자 실제 목록 조회');
select pg_temp.assert_true(pg_temp.fails(format('select public.resolve_review(%L,''rejected'','''')',:'review_id'),'22023'),'처리 사유 필수');
select public.resolve_review(:'review_id','rejected','비정상적인 평균 속도 확인');
select public.resolve_review(:'review_id','rejected','동일 결정 재시도');
select pg_temp.assert_true(pg_temp.fails(format('select public.resolve_review(%L,''approved'',''결정 변경'')',:'review_id'),'P0001'),'반대 결정 덮어쓰기 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.integrity_actions','42501'),'감사 원본 직접 조회 금지');
reset role;
select pg_temp.assert_true((select integrity_status='rejected' from public.runs where id=:'suspicious_run'),'기록 반려 확정');
select pg_temp.assert_true((select count(*)=1 from runspot_private.integrity_actions where case_id=:'review_id'),'감사 이력 중복 방지');
select pg_temp.assert_true((select count(*)=1 from runspot_private.audit_logs where target_id=:'suspicious_run'),'감사 로그 원자적 기록');
-- 기존 보상 지급 기록을 반려하면 현재 잔액·업적에서 제외하되 원본은 보존합니다.
select id as normal_run from public.runs where user_id='00000000-0000-0000-0000-000000000081' and id<>:'suspicious_run' order by ended_at limit 1 \gset
update public.runs set integrity_status='rejected' where id=:'normal_run';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true((public.my_run_reward(:'normal_run')->>'xp')::integer=0,'반려 보상 제외');
select pg_temp.assert_true(public.my_run_reward(:'normal_run')->>'reason'='rejected','반려 사유 제공');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.my_achievements())e where e->>'achieved_at' is null),'반려 후 10회·50km 업적 회수');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',true);
select pg_temp.assert_true((select bool_and((e->>'progress')::integer=0) from jsonb_array_elements(public.my_achievements())e),'타계정 업적 격리');
rollback;
