\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean, message text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.denied(statement text)
returns boolean language plpgsql security invoker as $$
begin
  execute statement; return false;
exception when insufficient_privilege then return true;
end;
$$;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000021');
update public.profiles set registration_completed_at=null where id='00000000-0000-0000-0000-000000000021';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select pg_temp.assert_true(not public.registration_test_mode(),'기본 비활성');
select pg_temp.assert_true(pg_temp.denied('select public.complete_test_registration()'),'미허용 테스트 가입 차단');
select pg_temp.assert_true(pg_temp.denied('update runspot_private.registration_test_settings set enabled_until=now()+interval ''1 day'''),'클라이언트 설정 변경 차단');
reset role;
update runspot_private.registration_test_settings set enabled_until=now()+interval '1 day';
set local role anon;
select pg_temp.assert_true(public.registration_test_mode(),'비로그인 화면에서 테스트 모드 확인');
select pg_temp.assert_true(pg_temp.denied('select public.complete_test_registration()'),'비로그인 완료 차단');
reset role;
set local role authenticated;
select public.complete_test_registration();
select public.complete_test_registration();
select pg_temp.assert_true(public.my_registration_complete(),'테스트 가입 허용');
select pg_temp.assert_true(runspot_private.is_active(auth.uid()),'테스트 개인 기능 허용');
select pg_temp.assert_true(not runspot_private.can_interact(),'전화번호 미인증 소셜 차단 유지');
select pg_temp.assert_true(pg_temp.denied('select public.set_my_nickname(''선점'')'),'미인증 닉네임 선점 차단 유지');
reset role;
select pg_temp.assert_true((select registration_completed_at is null from public.profiles where id='00000000-0000-0000-0000-000000000021'),'정식 가입 완료 위조 없음');
update runspot_private.registration_test_settings set enabled_until=now()-interval '1 second';
set local role authenticated;
select pg_temp.assert_true(not public.my_registration_complete(),'만료 후 정식 가입 필요');
select pg_temp.assert_true(not runspot_private.is_active(auth.uid()),'만료 후 테스트 접근 차단');
reset role;
set local role authenticated;
select public.complete_registration();
select pg_temp.assert_true(public.my_registration_complete(),'테스트 종료 후 정식 가입 전환');
reset role;
rollback;
