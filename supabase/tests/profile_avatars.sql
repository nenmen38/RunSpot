\set ON_ERROR_STOP on
begin;
create function pg_temp.check_avatar(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000981','avatar981@example.com',now()),
 ('00000000-0000-0000-0000-000000000982','avatar982@example.com',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000981',true);
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981') is null,'처음에는 사진 없음');
select pg_temp.check_avatar(pg_temp.fails($q$select public.set_my_avatar(encode('\x89504e47'::bytea,'base64'))$q$,'22023'),'JPEG가 아니면 거부');
select pg_temp.check_avatar(pg_temp.fails($q$select public.set_my_avatar('사진아님')$q$,'22023'),'base64가 아니면 거부');
select public.set_my_avatar(encode('\xffd800112233ffd9'::bytea,'base64'));
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981')=encode('\xffd800112233ffd9'::bytea,'base64'),'내 사진 저장');
select pg_temp.check_avatar(pg_temp.fails($q$select public.set_my_avatar(encode('\xffd8aaffd9'::bytea,'base64'))$q$,'P0001'),'연달아 바꾸기 제한');
-- 다른 사람도 볼 수 있지만, 차단 관계면 보이지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000982',true);
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981') is not null,'다른 사람에게 보임');
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values('00000000-0000-0000-0000-000000000981','00000000-0000-0000-0000-000000000982');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000982',true);
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981') is null,'차단 관계면 숨김');
-- 다른 사람 사진은 지울 수 없고, 내 사진만 지웁니다.
select public.remove_my_avatar();
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000981',true);
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981') is not null,'남의 삭제 요청은 영향 없음');
select public.remove_my_avatar();
select pg_temp.check_avatar(public.user_avatar('00000000-0000-0000-0000-000000000981') is null,'내 사진 삭제');
rollback;
