\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean, message text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.fails(statement text, expected text)
returns boolean language plpgsql security invoker as $$
begin
  execute statement;
  return false;
exception when others then return sqlstate=expected;
end;
$$;
insert into public.registration_terms(id,version,title,body,published_at,is_current)
values ('90000000-0000-0000-0000-000000000001','test','테스트 전용','검증용 본문',now(),true);
insert into public.registration_terms(id,version,title,body)
values ('90000000-0000-0000-0000-000000000002','draft','초안','미게시 본문');
insert into auth.users(id,raw_user_meta_data) values
('00000000-0000-0000-0000-000000000011','{"registration_nickname":"Runner","registration_terms_id":"90000000-0000-0000-0000-000000000001"}'),
('00000000-0000-0000-0000-000000000012','{"registration_completed_at":"2026-01-01","role":"admin"}');
select pg_temp.assert_true((select count(*)=1 from runspot_private.registration_consents),'동의 기록 서버 생성');
select pg_temp.assert_true(not exists(select 1 from public.profiles where nickname is not null),'메타데이터로 닉네임 선점 불가');
select pg_temp.assert_true(pg_temp.fails($q$update public.registration_terms set body='변조' where version='test'$q$,'P0001'),'게시 약관 불변');
set local role anon;
select pg_temp.assert_true((select count(*)=1 from public.registration_terms),'미게시 약관 노출 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('Runner')$q$,'42501'),'비로그인 닉네임 선점 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.complete_registration('90000000-0000-0000-0000-000000000001')$q$,'42501'),'비로그인 가입 완료 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
select pg_temp.assert_true(not public.my_registration_complete(),'메타데이터 완료 위조 차단');
select pg_temp.assert_true((select count(*)=0 from public.profiles),'미완료 프로필 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.complete_registration(null)$q$,'22023'),'약관 동의 필수');
select pg_temp.assert_true(pg_temp.fails($q$select public.complete_registration('90000000-0000-0000-0000-000000000002')$q$,'22023'),'미게시 약관 동의 차단');
select public.complete_registration('90000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(public.my_registration_complete(),'닉네임 없이 기본 가입 완료');
select pg_temp.assert_true((select count(*)=1 from public.profiles),'미인증 개인 프로필 접근 허용');
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('Runner')$q$,'42501'),'미인증 닉네임 선점 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.profiles set nickname='Runner' where id=auth.uid()$q$,'42501'),'직접 업데이트 우회 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.profiles set nickname_changed_at=now()-interval '31 days'$q$,'42501'),'변경 시각 조작 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.profiles set registration_completed_at=now()$q$,'42501'),'완료 상태 직접 변경 차단');
select pg_temp.assert_true(pg_temp.fails($q$select * from runspot_private.registration_consents$q$,'42501'),'동의 내역 직접 접근 차단');
reset role;
update auth.users set phone='+821012345678',phone_confirmed_at=now() where id='00000000-0000-0000-0000-000000000012';
set local role authenticated;
select pg_temp.assert_true(not runspot_private.can_interact(),'인증 후 닉네임 미등록 소셜 차단');
select pg_temp.assert_true(pg_temp.fails($q$update public.profiles set visibility='public' where id=auth.uid()$q$,'42501'),'닉네임 미등록 공개 변경 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('공 백')$q$,'22023'),'닉네임 형식 검증');
select public.set_my_nickname('Runner');
select public.set_my_nickname('Runner');
select pg_temp.assert_true(runspot_private.can_interact(),'인증된 비공개 사용자 소셜 허용');
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('다른이름')$q$,'P0001'),'30일 내 변경 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname(null)$q$,'22023'),'닉네임 삭제 차단');
reset role;
update auth.users set phone='+821012345679',phone_confirmed_at=now() where id='00000000-0000-0000-0000-000000000011';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('runner')$q$,'23505'),'대소문자 중복 차단');
select pg_temp.assert_true((select nickname is null and nickname_changed_at is null from public.profiles where id=auth.uid()),'중복 실패 시 변경 시각 롤백');
select public.set_my_nickname('새러너');
reset role;
-- 시간 경과는 격리된 테스트 트랜잭션에서만 재현합니다.
alter table public.profiles disable trigger validate_nickname;
update public.profiles set nickname_changed_at=now()-interval '30 days' where id='00000000-0000-0000-0000-000000000011';
alter table public.profiles enable trigger validate_nickname;
set local role authenticated;
select public.set_my_nickname('새이름');
select pg_temp.assert_true((select nickname='새이름' and nickname_changed_at=now() from public.profiles where id=auth.uid()),'30일 경계 변경 허용');
reset role;
update auth.users set phone_change='+821099999999' where id='00000000-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select public.set_my_nickname('또다른이름')$q$,'42501'),'번호 변경 중 닉네임 변경 차단');
select pg_temp.assert_true(not runspot_private.can_interact(),'번호 변경 중 소셜 차단');
select pg_temp.assert_true(public.my_registration_complete(),'번호 변경 중 개인 기능 유지');
reset role;
select pg_temp.assert_true((select count(*)=2 from runspot_private.registration_consents),'사용자별 동의 기록 유지');
rollback;
