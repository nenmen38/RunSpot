\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000081');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":500000000},{"distance_m":1000,"duration_us":100000000}]');
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":500000000},{"distance_m":1000,"duration_us":100000000}]');
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),2000,480,'[]',null,null,
 '[{"distance_m":1000,"duration_us":240000000},{"distance_m":1000,"duration_us":240000000}]');
reset role;
select pg_temp.assert_true((select count(*)=2 from runspot_private.integrity_cases where rule_code='split_speed_over_6_5'),'전체 평균이 정상인 고속 구간 검토');
select pg_temp.assert_true(not runspot_private.has_suspicious_splits('[{"distance_m":650,"duration_us":100000000}]'),'속도 경계는 초과만 판정');
select pg_temp.assert_true(not runspot_private.has_suspicious_splits('[{"distance_m":1,"duration_us":0}]'),'짧은 마지막 구간의 흔들림 제외');
select pg_temp.assert_true(runspot_private.has_suspicious_splits('[{"distance_m":300,"duration_us":0}]'),'시간 없는 유효 길이 구간 검토');
select pg_temp.assert_true(not has_function_privilege('anon','runspot_private.has_suspicious_splits(jsonb)','execute'),'익명 내부 판정 접근 차단');
select pg_temp.assert_true(not has_function_privilege('authenticated','runspot_private.has_suspicious_splits(jsonb)','execute'),'일반 사용자 내부 판정 접근 차단');
rollback;
\echo '구간 이상 속도 검토 테스트 통과'
