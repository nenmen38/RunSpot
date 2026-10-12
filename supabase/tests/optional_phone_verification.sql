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

insert into auth.users(id,phone,phone_confirmed_at,email,email_confirmed_at,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000071','821011111111',now(),'phoneonly@example.com',null,'{}'),
 ('00000000-0000-0000-0000-000000000072','821022222222',null,'emailonly@example.com',now(),'{"phone_verified":true}');
set local role anon;
select pg_temp.assert_true(pg_temp.denied('select public.my_phone_verification_state()'),'비로그인 전화번호 상태 조회 거절');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(pg_temp.denied('select public.my_phone_verification_state()'),'빈 인증 세션 거절');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select pg_temp.assert_true((public.my_phone_verification_state()->>'verified')::boolean,'서버 전화번호 확인 상태 조회');
select pg_temp.assert_true(public.my_phone_verification_state()->>'phone'='821011111111','현재 사용자 번호만 반환');
select pg_temp.assert_true(not public.my_email_verified() and not runspot_private.can_interact(),'전화번호 확인만으로 이메일 소셜 권한 우회 불가');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
select pg_temp.assert_true(not (public.my_phone_verification_state()->>'verified')::boolean,'사용자 메타데이터로 전화번호 확인 우회 불가');
select public.set_my_nickname('이메일선택인증');
update public.profiles set visibility='friends' where id=auth.uid();
reset role;
update auth.users set phone_confirmed_at=now(),phone_change='821033333333' where id='00000000-0000-0000-0000-000000000072';
set local role authenticated;
select pg_temp.assert_true(not (public.my_phone_verification_state()->>'verified')::boolean,'번호 변경 중 인증 상태 거절');
select pg_temp.assert_true(public.my_phone_verification_state()->>'pending_phone'='821033333333','본인 변경 예정 번호 반환');
select pg_temp.assert_true(public.my_email_verified() and runspot_private.can_interact(),'선택 전화번호 변경은 이메일 소셜 권한에 영향 없음');
select pg_temp.assert_true((select visibility='friends' from public.profiles where id=auth.uid()),'선택 전화번호 변경으로 공개 범위를 바꾸지 않음');
reset role;
update auth.users set phone='',phone_change='' where id='00000000-0000-0000-0000-000000000072';
set local role authenticated;
select pg_temp.assert_true(not (public.my_phone_verification_state()->>'verified')::boolean,'확인 시각만 있고 번호가 없으면 미인증');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000072';
set local role authenticated;
select pg_temp.assert_true(pg_temp.denied('select public.my_phone_verification_state()'),'정지 계정 인증 조회 차단');
reset role;
select pg_temp.assert_true(not (select prosecdef from pg_proc where oid='public.my_phone_verification_state()'::regprocedure),'공개 RPC는 호출자 권한으로 실행');
rollback;
\echo '선택 전화번호 인증 조회 및 이메일 권한 분리 테스트 통과'
