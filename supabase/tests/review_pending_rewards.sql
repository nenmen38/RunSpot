\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000081','hold81@example.com',now()),
 ('00000000-0000-0000-0000-000000000082','review82@example.com',now()),
 ('00000000-0000-0000-0000-000000000083','hold83@example.com',now());
update public.profiles set nickname='보류'||right(id::text,2),visibility='friends';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000082','moderator');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":500000000},{"distance_m":1000,"duration_us":100000000}]') as saved \gset
select (:'saved'::jsonb->>'id')::uuid as held_id \gset
select pg_temp.assert_true((:'saved'::jsonb->>'review_pending')::boolean,'저장 응답에서 서버 보류 상태 제공');
select pg_temp.assert_true((public.my_run_reward(:'held_id')->>'xp')::int=0 and public.my_run_reward(:'held_id')->>'reason'='review_pending','보류 보상 표시');
select pg_temp.assert_true((public.my_progress()->>'total_xp')::int=0,'보류 경험치 잔액 제외');
select pg_temp.assert_true((public.friend_weekly_ranking()->'entries'->0->>'distance_m')::int=0,'보류 거리 랭킹 제외');
select pg_temp.assert_true((public.my_run_statistics()->>'weekly_distance_m')::int=2000,'개인 측정 기록 보존');
select pg_temp.assert_true((select bool_and((e->>'progress')::int=0) from jsonb_array_elements(public.my_achievements())e),'보류 업적 제외');
select pg_temp.assert_true(pg_temp.fails('update public.runs set review_pending=false','42501'),'직접 보류 해제 차단');
select pg_temp.assert_true(pg_temp.fails(format('select runspot_private.settle_run_reward(%L)',:'held_id'),'42501'),'일반 사용자 보상 지급 차단');
-- 전송 재시도 중에도 검토 건과 보류 보상 원본을 중복 생성하지 않습니다.
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":500000000},{"distance_m":1000,"duration_us":100000000}]');
select public.save_my_run('10000000-0000-0000-0000-000000000084',now()-interval '4 hours',now(),30000,10000);
reset role;
select pg_temp.assert_true((select count(*)=1 from runspot_private.run_rewards where run_id=:'held_id'),'보류 보상 원본 한 건');
select id as held_case from runspot_private.integrity_cases where run_id=:'held_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.resolve_review(%L,''approved'',''확인'')',:'held_case'),'42501'),'승인에 다중 인증 필요');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select public.resolve_review(:'held_case','approved','GPS 및 실제 러닝 확인');
select public.resolve_review(:'held_case','approved','재시도');
reset role;
select pg_temp.assert_true((select not review_pending and integrity_status='verified' from public.runs where id=:'held_id'),'승인 시 보류 해제');
select pg_temp.assert_true((select count(*)=1 from runspot_private.integrity_actions where case_id=:'held_case'),'승인 이력 중복 방지');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true((public.my_run_reward(:'held_id')->>'xp')::int=30,'승인 후 한 번 지급');
select pg_temp.assert_true((public.my_progress()->>'total_xp')::int=330,'승인 보상 잔액 반영');
select pg_temp.assert_true((public.friend_weekly_ranking()->'entries'->0->>'distance_m')::int=32000,'승인 랭킹 거리 복구');
-- 전체 평균이 빠른 구버전 저장 경로도 동일하게 보류합니다.
select (public.save_my_run('10000000-0000-0000-0000-000000000085',now()-interval '3 hours',now(),50000,6000)->>'id')::uuid as cap_id \gset
select (public.save_my_run('10000000-0000-0000-0000-000000000086',now()-interval '1 hour',now(),6000,600)->>'id')::uuid as rejected_id \gset
reset role;
select id as cap_case from runspot_private.integrity_cases where run_id=:'cap_id' \gset
select id as reject_case from runspot_private.integrity_cases where run_id=:'rejected_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select public.resolve_review(:'cap_case','approved','실제 러닝 확인');
select public.resolve_review(:'reject_case','rejected','이동 수단 사용 확인');
select public.resolve_review(:'reject_case','rejected','재시도');
select pg_temp.assert_true(pg_temp.fails(format('select public.resolve_review(%L,''approved'',''결정 변경'')',:'reject_case'),'P0001'),'반려 후 반대 결정 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true((public.my_run_reward(:'cap_id')->>'xp')::int=170,'승인 지급도 원래 러닝 날짜의 일일 한도 준수');
select pg_temp.assert_true((public.my_progress()->>'total_xp')::int=500,'보류·승인 혼합 일일 한도');
select pg_temp.assert_true((public.my_run_reward(:'rejected_id')->>'xp')::int=0 and public.my_run_reward(:'rejected_id')->>'reason'='rejected','반려 기록 보상 제외');
select pg_temp.assert_true((public.friend_weekly_ranking()->'entries'->0->>'distance_m')::int=82000,'반려 거리 랭킹 제외');
-- 검토 대기가 오래 걸렸다는 이유만으로 정상 접수 원본을 지연 전송으로 바꾸지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',true);
select (public.save_my_run('10000000-0000-0000-0000-000000000087',now()-interval '1 hour',now(),2000,200)->>'id')::uuid as delayed_id \gset
reset role;
update public.runs set started_at=started_at-interval '8 days',ended_at=ended_at-interval '8 days' where id=:'delayed_id';
update runspot_private.run_rewards set awarded_at=awarded_at-interval '8 days' where run_id=:'delayed_id';
select id as delayed_case from runspot_private.integrity_cases where run_id=:'delayed_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select public.resolve_review(:'delayed_case','approved','지연 검토 완료');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000083',true);
select pg_temp.assert_true((public.my_run_reward(:'delayed_id')->>'xp')::int=30,'오래 걸린 검토의 정상 보상');
select pg_temp.assert_true(public.my_run_reward(:'held_id')->>'status'='unavailable','타인 보류·승인 보상 조회 차단');
reset role;
rollback;
\echo '의심 기록 보류·승인 지급·반려·권한 검증 통과'
