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
 ('00000000-0000-0000-0000-000000000121'),
 ('00000000-0000-0000-0000-000000000122');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select * from public.run_location_preferences','42501'),'비로그인 설정 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000121',true);
select pg_temp.assert_true((select count(*)=0 from public.run_location_preferences),'미설정 계정은 행 없음');
insert into public.run_location_preferences(user_id) values(auth.uid());
select pg_temp.assert_true((select enabled=false from public.run_location_preferences),'기본값 꺼짐');
insert into public.run_location_preferences(user_id,enabled) values(auth.uid(),true)
on conflict(user_id) do update set enabled=excluded.enabled;
select pg_temp.assert_true((select enabled from public.run_location_preferences),'본인 설정 저장');
select pg_temp.assert_true((select visibility='private' from public.profiles where id=auth.uid()),'설정 저장이 공개 범위를 확대하지 않음');
select pg_temp.assert_true(pg_temp.fails($q$insert into public.run_location_preferences(user_id,enabled)
values('00000000-0000-0000-0000-000000000122',true)$q$,'42501'),'타인 설정 생성 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.run_location_preferences
set user_id='00000000-0000-0000-0000-000000000122'$q$,'42501'),'소유권 변경 차단');
select pg_temp.assert_true(pg_temp.fails('delete from public.run_location_preferences','42501'),'직접 삭제 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000122',true);
select pg_temp.assert_true((select count(*)=0 from public.run_location_preferences),'타인 설정 조회 차단');
update public.run_location_preferences set enabled=false;
reset role;
select pg_temp.assert_true((select enabled from public.run_location_preferences where
 user_id='00000000-0000-0000-0000-000000000121'),'타인 설정 변경 차단');
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000121';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000121',true);
select pg_temp.assert_true((select count(*)=0 from public.run_location_preferences),'정지 계정 조회 차단');
select pg_temp.assert_true(pg_temp.fails('insert into public.run_location_preferences(user_id,enabled) values(auth.uid(),false) on conflict(user_id) do update set enabled=false','42501'),'정지 계정 저장 차단');
reset role;
rollback;
\echo '러닝 위치 공유 설정의 기본값·계정 분리·권한 테스트 통과'
