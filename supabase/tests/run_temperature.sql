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
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),100,60,'[]',20,now())$q$,'42501'),'비로그인 저장 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true((public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),100,60,'[[[37,127]]]',23.5,now()-interval '30 minutes')->>'temperature_c')::double precision=23.5,'기온 저장 응답');
select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),100,60,'[[[37,127]]]',23.5,now()-interval '30 minutes');
select pg_temp.assert_true((select count(*)=1 from public.runs),'중복 재전송 한 건');
select pg_temp.assert_true((select temperature_c=23.5 and temperature_observed_at=now()-interval '30 minutes' from public.runs),'기온과 관측 시각 조회');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000081',now()-interval '1 hour',now(),100,60,'[[[37,127]]]',24,now()-interval '30 minutes')$q$,'22023'),'재시도 기온 변경 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.runs set temperature_c=24$q$,'42501'),'직접 기온 변경 차단');
select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000082',now()-interval '1 hour',now(),0,0,'[]',null,null);
select pg_temp.assert_true((select temperature_c is null and temperature_observed_at is null from public.runs where client_run_id='10000000-0000-0000-0000-000000000082'),'자료 없음 보존');
select public.save_my_run_with_route('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),0,0,'[]');
select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),0,0,'[]',null,null);
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000083',now()-interval '1 hour',now(),0,0,'[]',20,now())$q$,'22023'),'기존 기록 기온 임의 추가 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]',20,null)$q$,'22023'),'관측 시각 필수');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]',null,now())$q$,'22023'),'기온 필수');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]',20,now()-interval '121 minutes')$q$,'22023'),'오래된 관측 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]',20,now()+interval '16 minutes')$q$,'22023'),'미래 관측 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]','NaN',now())$q$,'22023'),'비수치 기온 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[]',61,now())$q$,'22023'),'기온 범위 검사');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000084',now()-interval '1 hour',now(),100,60,'[[[91,127]]]',20,now())$q$,'22023'),'경로 오류 시 함께 취소');
select pg_temp.assert_true((select count(*)=3 from public.runs),'잘못된 기록 부분 저장 없음');
-- 재전송 시 현재 시각이 아니라 원래 종료 시각을 기준으로 검증합니다.
select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000085',now()-interval '2 days 1 hour',now()-interval '2 days',100,60,'[]',-3.2,now()-interval '2 days 1 hour');
select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000085',now()-interval '2 days 1 hour',now()-interval '2 days',100,60,'[]',-3.2,now()-interval '2 days 1 hour');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select pg_temp.assert_true((select count(*)=0 from public.runs),'다른 계정의 기온 조회 차단');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000081';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_temperature('10000000-0000-0000-0000-000000000086',now()-interval '1 hour',now(),0,0,'[]',20,now())$q$,'42501'),'정지 계정 저장 차단');
reset role;
rollback;
\echo '러닝 종료 기온 저장 및 권한 테스트 통과'
