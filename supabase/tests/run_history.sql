\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.fails(statement text,expected_code text)
returns boolean language plpgsql security invoker as $$
begin execute statement; return false;
exception when others then return sqlstate=expected_code; end;
$$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000081'),
 ('00000000-0000-0000-0000-000000000082');
set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),5000,1500)$q$,'42501'),'비로그인 저장 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000081',true);
-- 전화번호 인증이 없어도 비공개 개인 기록은 저장할 수 있습니다.
select public.save_my_run('10000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),5000,1500);
select public.save_my_run('10000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),5000,1500);
select pg_temp.assert_true((select count(*)=1 from public.runs),'재시도 중복 저장 방지');
select pg_temp.assert_true((select integrity_status='pending' from public.runs),'검증 완료로 위장하지 않음');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),6000,1500)$q$,'22023'),'동일 식별자 내용 변조 차단');
select public.save_my_run('10000000-0000-0000-0000-000000000002',now()-interval '1 second',now(),0,0);
select pg_temp.assert_true((select count(*)=2 from public.runs),'정지한 러닝과 짧은 러닝 저장');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000003',now()-interval '1 second',now(),-1,0)$q$,'22023'),'음수 거리 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000003',now()-interval '1 second',now(),1000001,0)$q$,'22023'),'과도한 거리 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000003',now()-interval '1 second',now(),1,100)$q$,'22023'),'경과 시간보다 긴 측정 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000003',now(),now()+interval '1 hour',1,1)$q$,'22023'),'미래 종료 시각 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000003','-infinity',now(),1,1)$q$,'22023'),'무한 날짜 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.runs set integrity_status='verified'$q$,'42501'),'검증 상태 직접 변경 차단');
select pg_temp.assert_true(pg_temp.fails($q$insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
  values('00000000-0000-0000-0000-000000000082','10000000-0000-0000-0000-000000000003',now()-interval '1 hour',now(),1,1)$q$,'42501'),'직접 쓰기와 타인 명의 저장 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select pg_temp.assert_true((select count(*)=0 from public.runs),'타인 개인 기록 조회 차단');
select public.save_my_run('10000000-0000-0000-0000-000000000001',now()-interval '1 minute',now(),100,30);
select pg_temp.assert_true((select count(*)=1 and bool_and(user_id='00000000-0000-0000-0000-000000000082') from public.runs),'다른 사용자의 동일 식별자는 본인 소유');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000082';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run(
  '10000000-0000-0000-0000-000000000004',now()-interval '1 minute',now(),100,30)$q$,'42501'),'정지 계정 저장 차단');
select pg_temp.assert_true((select count(*)=0 from public.runs),'정지 계정 조회 차단');
reset role;
rollback;
\echo '러닝 기록 저장 및 권한 테스트 통과'
