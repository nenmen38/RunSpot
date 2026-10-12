\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.denied(statement text)
returns boolean language plpgsql security invoker as $$
begin execute statement; return false;
exception when insufficient_privilege then return true; end;
$$;

insert into auth.users(id,email,phone,phone_confirmed_at,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000061','unconfirmed@example.com','821012345678',now(),'{"email_verified":true,"email_confirmed_at":"2026-01-01"}'),
 ('00000000-0000-0000-0000-000000000062','confirmed@example.com',null,null,'{}'),
 ('00000000-0000-0000-0000-000000000063',null,null,null,'{}');
update auth.users set email_confirmed_at=now() where id='00000000-0000-0000-0000-000000000062';
select pg_temp.assert_true((select visibility='private' and nickname is null from public.profiles where id='00000000-0000-0000-0000-000000000062'),'이메일 인증만으로 공개하거나 닉네임을 자동 등록하지 않음');
set local role anon;
select pg_temp.assert_true(pg_temp.denied('select public.my_email_verified()'),'비로그인 인증 상태 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(not public.my_email_verified(),'빈 로그인 세션 인증 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select set_config('request.jwt.claims','{"email":"unconfirmed@example.com","email_verified":true,"phone":"821012345678"}',true);
select pg_temp.assert_true(not public.my_email_verified(),'전화번호 확인과 위조 메타데이터·토큰으로 이메일 인증 우회 불가');
select pg_temp.assert_true(pg_temp.denied('select public.set_my_nickname(''미인증'')'),'이메일 미인증 닉네임 등록 차단');
select pg_temp.assert_true(pg_temp.denied('update public.profiles set visibility=''public'' where id=auth.uid()'),'이메일 미인증 공개 설정 차단');
select pg_temp.assert_true(pg_temp.denied('select public.update_my_live_location(37,127,10)'),'전화번호만 확인한 계정의 위치 업로드 차단');
select pg_temp.assert_true(pg_temp.denied('select runspot_private.email_verified(''00000000-0000-0000-0000-000000000062'')'),'타인 이메일 확인 상태 직접 조회 차단');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000062',true);
select pg_temp.assert_true(public.my_email_verified(),'전화번호 없이 이메일 확인만으로 인증 허용');
select pg_temp.assert_true(not runspot_private.can_interact(),'이메일 확인 후에도 닉네임 등록은 필요');
select public.set_my_nickname('이메일러너');
select pg_temp.assert_true(runspot_private.can_interact(),'이메일과 닉네임 확인 후 소셜 허용');
select pg_temp.assert_true((select visibility='private' from public.profiles where id=auth.uid()),'닉네임 등록 후에도 비공개 유지');
update public.profiles set visibility='friends' where id=auth.uid();
select public.update_my_live_location(37,127,10);
reset role;
select pg_temp.assert_true(exists(select 1 from runspot_private.live_locations where user_id='00000000-0000-0000-0000-000000000062'),'이메일 확인 계정의 위치 업로드 허용');

update auth.users set email_change='next@example.com' where id='00000000-0000-0000-0000-000000000062';
select pg_temp.assert_true((select visibility='private' and nickname='이메일러너' from public.profiles where id='00000000-0000-0000-0000-000000000062'),'이메일 변경 중 비공개 초기화와 닉네임 보존');
select pg_temp.assert_true(not exists(select 1 from runspot_private.live_locations where user_id='00000000-0000-0000-0000-000000000062'),'인증 회수 시 기존 공개 위치 원본 제거');
set local role authenticated;
select pg_temp.assert_true(not public.my_email_verified(),'기존 확인 시각과 오래된 토큰이 있어도 변경 중 이메일은 미인증');
select pg_temp.assert_true(not runspot_private.can_interact(),'이메일 변경 중 소셜 권한 회수');
select pg_temp.assert_true(public.my_registration_complete(),'이메일 변경 중 개인 가입 상태 보존');
select pg_temp.assert_true(pg_temp.denied('select public.update_my_live_location(37,127,10)'),'이메일 변경 중 재업로드 차단');
reset role;
update auth.users set email='next@example.com',email_change='' where id='00000000-0000-0000-0000-000000000062';
set local role authenticated;
select pg_temp.assert_true(public.my_email_verified(),'이메일 변경 확인 완료 후 인증 복원');
select pg_temp.assert_true((select visibility='private' from public.profiles where id=auth.uid()),'재인증 후 위치 공개를 자동 복원하지 않음');
update public.profiles set visibility='public' where id=auth.uid();
reset role;
update auth.users set phone_change='821099999999' where id='00000000-0000-0000-0000-000000000062';
select pg_temp.assert_true((select visibility='public' from public.profiles where id='00000000-0000-0000-0000-000000000062'),'전화번호 변경은 이메일 인증 권한에 영향을 주지 않음');
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000062';
set local role authenticated;
select pg_temp.assert_true(not public.my_email_verified(),'이메일 확인 해제는 즉시 반영');
reset role;
update auth.users set email='anonymous@example.com',email_confirmed_at=now(),is_anonymous=true where id='00000000-0000-0000-0000-000000000063';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000063',true);
select pg_temp.assert_true(not public.my_email_verified(),'익명 계정은 확인 시각만으로 인증 불가');
reset role;
update auth.users set email='',is_anonymous=false where id='00000000-0000-0000-0000-000000000063';
set local role authenticated;
select pg_temp.assert_true(not public.my_email_verified(),'이메일이 없으면 확인 시각이 있어도 미인증');
reset role;
rollback;
\echo '이메일 인증 및 권한 회수 테스트 통과'
