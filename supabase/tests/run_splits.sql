\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.fails(statement text,expected_code text)
returns boolean language plpgsql as $$
begin execute statement; return false;
exception when others then return sqlstate=expected_code; end;
$$;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000081'),('00000000-0000-0000-0000-000000000082');
set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),1250,400,'[]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":250,"duration_us":100000000}]')$q$,'42501'),'익명 저장 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true(jsonb_array_length(public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),1250,400,'[[[37,127]]]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":250,"duration_us":100000000}]')->'split_data')=2,'구간 저장 응답');
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),1250,400,'[[[37,127]]]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":250,"duration_us":100000000}]');
select pg_temp.assert_true((select count(*)=1 from public.runs),'동일 재전송 중복 방지');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),1250,400,'[[[37,127]]]',null,null,'[{"distance_m":1000,"duration_us":200000000},{"distance_m":250,"duration_us":200000000}]')$q$,'22023'),'구간 변경 재전송 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":300,"duration_us":100000000}]')$q$,'22023'),'거리 합계 불일치 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":250,"duration_us":99999999}]')$q$,'22023'),'활동 시간 합계 불일치 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[]',null,null,'[{"distance_m":250,"duration_us":100000000},{"distance_m":1000,"duration_us":300000000}]')$q$,'22023'),'마지막 외 짧은 구간 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[]',null,null,'[{"distance_m":1000,"duration_us":-1},{"distance_m":250,"duration_us":400000001}]')$q$,'22023'),'음수 구간 시간 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[]',null,null,'{}')$q$,'22023'),'구간 형식 검사');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),1250,400,'[[[91,127]]]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":250,"duration_us":100000000}]')$q$,'22023'),'경로 오류 시 전체 취소');
select pg_temp.assert_true((select count(*)=1 from public.runs),'오류 뒤 부분 저장 없음');
select pg_temp.assert_true(pg_temp.fails($q$update public.runs set split_data='[]'$q$,'42501'),'구간 직접 변경 차단');
-- 정지 기록·구버전 전송 대기·거리 및 시간 반올림을 지원합니다.
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),0,10,'[]',null,null,'[]');
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),200,60,'[]',null,null,null);
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),1000,300,'[]',null,null,'[{"distance_m":1000,"duration_us":300999999}]');
select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000085',now()-interval '1 hour',now(),1001,300,'[]',null,null,'[{"distance_m":1000,"duration_us":300000000},{"distance_m":0.51,"duration_us":500}]');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),200,60,'[]',null,null,'[{"distance_m":200,"duration_us":60000000}]')$q$,'22023'),'기존 기록 임의 구간 채우기 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select pg_temp.assert_true((select count(*)=0 from public.runs),'타인 구간 조회 차단');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000082';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_splits('10000000-0000-0000-0000-000000000086',now()-interval '1 hour',now(),0,10,'[]',null,null,'[]')$q$,'42501'),'정지 계정 구간 저장 차단');
reset role;
rollback;
\echo '구간 기록 저장·권한·동일 재전송 검증 통과'
