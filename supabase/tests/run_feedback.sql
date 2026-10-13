\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.denied(statement text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when insufficient_privilege then return true; end;
$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000081','feedback1@example.com',now()),
 ('00000000-0000-0000-0000-000000000082','feedback2@example.com',now()),
 ('00000000-0000-0000-0000-000000000083','feedback3@example.com',null);
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec) values
 ('10000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000081',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',3000,1200),
 ('10000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000081',gen_random_uuid(),now()-interval '1 day',now()-interval '23 hours',2000,1000),
 ('10000000-0000-0000-0000-000000000083','00000000-0000-0000-0000-000000000082',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',1000,600),
 ('10000000-0000-0000-0000-000000000084','00000000-0000-0000-0000-000000000083',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',1000,600),
 ('10000000-0000-0000-0000-000000000085','00000000-0000-0000-0000-000000000081',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',0,0);
set local role anon;
select pg_temp.assert_true(pg_temp.denied('select public.my_run_feedback(''10000000-0000-0000-0000-000000000081'')'),'비로그인 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(pg_temp.denied('select public.my_run_feedback(''10000000-0000-0000-0000-000000000081'')'),'빈 세션 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true(public.my_run_feedback('10000000-0000-0000-0000-000000000081')->>'status'='available','본인 정상 기록 요청 가능');
select pg_temp.assert_true(public.my_run_feedback('10000000-0000-0000-0000-000000000085')->>'status'='insufficient_data','이동하지 않은 기록 분석 차단');
select pg_temp.assert_true(pg_temp.denied('select public.my_run_feedback(''10000000-0000-0000-0000-000000000083'')'),'타인 기록 조회 차단');
select pg_temp.assert_true(pg_temp.denied('select public.reserve_run_feedback(auth.uid(),''10000000-0000-0000-0000-000000000081'')'),'클라이언트 예약 권한 차단');
select pg_temp.assert_true(pg_temp.denied('select public.finish_run_feedback(gen_random_uuid(),''위조'',1,1)'),'클라이언트 피드백 쓰기 차단');
select pg_temp.assert_true(pg_temp.denied('select * from runspot_private.feedback_requests'),'원본 이력 직접 조회 차단');
reset role;
create temporary table reservation as select public.reserve_run_feedback('00000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000081') as data;
select pg_temp.assert_true((select data->>'status'='reserved' from reservation),'서버 예약 성공');
select pg_temp.assert_true((select (data#>>'{summary,previous,count}')::integer=1 and
 (data#>>'{summary,previous,pace_seconds_per_km}')::integer=500 from reservation),'이전 기록 합산 페이스 계산');
select pg_temp.assert_true((select not (data->'summary')::text ~ '(email|phone|latitude|longitude|user_id)' from reservation),'요약 식별자 및 좌표 제외');
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000082')->>'status'='cooldown','다른 기록에서도 72시간 제한');
select public.finish_run_feedback((select (data->>'request_id')::uuid from reservation),'이번 러닝 기록을 남기셨습니다. 이전보다 페이스 값이 작습니다. 환경 차이를 고려해 기록을 살펴보세요.',200,100);
select public.finish_run_feedback((select (data->>'request_id')::uuid from reservation),'중복 응답',200,100);
set local role authenticated;
select pg_temp.assert_true(public.my_run_feedback('10000000-0000-0000-0000-000000000081')->>'status'='ready','저장된 피드백 반복 조회');
select pg_temp.assert_true((select message<>'중복 응답' from public.run_feedback where run_id='10000000-0000-0000-0000-000000000081'),'중복 저장이 원래 결과를 바꾸지 않음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select pg_temp.assert_true((select count(*)=0 from public.run_feedback where run_id='10000000-0000-0000-0000-000000000081'),'피드백 RLS 타인 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',true);
select pg_temp.assert_true(public.my_run_feedback('10000000-0000-0000-0000-000000000084')->>'status'='email_required','이메일 미인증 요청 차단');
reset role;
update auth.users set email_change='next@example.com' where id='00000000-0000-0000-0000-000000000082';
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000082','10000000-0000-0000-0000-000000000083')->>'status'='email_required','변경 중 이메일의 과거 인증으로 우회 불가');
update auth.users set email_change='' where id='00000000-0000-0000-0000-000000000082';
update runspot_private.feedback_requests set created_at=now()-interval '72 hours'+interval '1 minute';
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000082')->>'status'='cooldown','72시간 경계 직전 차단');
update runspot_private.feedback_requests set created_at=now()-interval '72 hours';
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000082')->>'status'='reserved','72시간 경과 후 허용');
select public.finish_run_feedback((select id from runspot_private.feedback_requests order by created_at desc limit 1),null,0,0);
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000082')->>'status'='cooldown','실패한 요청도 재호출 제한');
delete from public.runs where id='10000000-0000-0000-0000-000000000082';
select pg_temp.assert_true((select count(*)=2 from runspot_private.feedback_requests),'기록 삭제로 요청 예산 복원 불가');
update runspot_private.feedback_limits set daily_calls=1;
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000082','10000000-0000-0000-0000-000000000083')->>'status'='budget_exhausted','전체 일일 한도 차단');
update runspot_private.feedback_limits set daily_calls=100,monthly_calls=2;
select pg_temp.assert_true(public.reserve_run_feedback('00000000-0000-0000-0000-000000000082','10000000-0000-0000-0000-000000000083')->>'status'='budget_exhausted','전체 30일 한도 차단');
update runspot_private.feedback_limits set monthly_calls=1000;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000082';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select pg_temp.assert_true(pg_temp.denied('select public.my_run_feedback(''10000000-0000-0000-0000-000000000083'')'),'정지 계정 조회 차단');
reset role;
delete from auth.users where id='00000000-0000-0000-0000-000000000081';
select pg_temp.assert_true((select count(*)=2 from runspot_private.feedback_requests),'계정 삭제 후에도 전체 호출 예산 보존');
select pg_temp.assert_true((select not prosecdef from pg_proc where oid='public.my_run_feedback(uuid)'::regprocedure),'공개 API 호출자 권한 유지');
rollback;
\echo '러닝 피드백 권한·72시간·예산 테스트 통과'
