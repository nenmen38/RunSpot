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
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000071','block71@example.com',now()),
 ('00000000-0000-0000-0000-000000000072','block72@example.com',now()),
 ('00000000-0000-0000-0000-000000000073','block73@example.com',now());
update public.profiles set nickname='차단검증'||right(id::text,2),visibility='public'
where id::text like '%00000000007_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000072','00000000-0000-0000-0000-000000000071','accepted');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.my_blocks()','42501'),'비로그인 차단 목록 거부');
select pg_temp.assert_true(pg_temp.fails('select public.change_my_block(''00000000-0000-0000-0000-000000000072'',true)','42501'),'비로그인 변경 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select pg_temp.assert_true(pg_temp.fails('select public.change_my_block(''00000000-0000-0000-0000-000000000071'',true)','22023'),'본인 차단 거부');
select pg_temp.assert_true(pg_temp.fails('select public.change_my_block(''00000000-0000-0000-0000-000000000099'',true)','42501'),'존재하지 않는 대상 차단 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.blocks','42501'),'차단 원본 접근 거부');
select public.change_my_block('00000000-0000-0000-0000-000000000072',true);
select public.change_my_block('00000000-0000-0000-0000-000000000072',true);
select pg_temp.assert_true((select count(*)=1 from public.my_blocks()),'중복 차단 멱등성');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'차단 시 친구 삭제');
select pg_temp.assert_true((select count(*)=0 from public.search_friend('차단검증72')),'차단한 상대 검색 제외');
select pg_temp.assert_true(not runspot_private.can_view_location('00000000-0000-0000-0000-000000000072'),'차단한 상대 위치 접근 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
select pg_temp.assert_true((select count(*)=0 from public.my_blocks()),'타인의 차단 목록 비공개');
select pg_temp.assert_true((select count(*)=0 from public.search_friend('차단검증71')),'역방향 검색 제외');
select public.change_my_block('00000000-0000-0000-0000-000000000071',false);
select pg_temp.assert_true((select count(*)=0 from public.search_friend('차단검증71')),'상대방의 차단 해제 불가');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000073',true);
select pg_temp.assert_true((select count(*)=0 from public.my_blocks()),'제삼자에게 차단 목록 비공개');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select public.change_my_block('00000000-0000-0000-0000-000000000072',false);
select public.change_my_block('00000000-0000-0000-0000-000000000072',false);
select pg_temp.assert_true((select count(*)=0 from public.my_blocks()),'차단 해제 멱등성');
select pg_temp.assert_true((select count(*)=1 from public.search_friend('차단검증72')),'해제 후 공개 상대 검색 가능');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'차단 해제 후 친구 자동 복원 금지');
reset role;
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000072';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.change_my_block(''00000000-0000-0000-0000-000000000072'',true)','42501'),'접근할 수 없는 비공개 대상 탐색 거부');
reset role;
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000071';
insert into public.friendships(user_low,user_high,requested_by) values
 ('00000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000072','00000000-0000-0000-0000-000000000072');
set local role authenticated;
select public.change_my_block('00000000-0000-0000-0000-000000000072',true);
select pg_temp.assert_true((select count(*)=1 from public.my_blocks()),'미인증 사용자도 받은 요청 상대 차단 가능');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'차단 시 대기 요청 삭제');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000071';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.my_blocks()','42501'),'정지 계정 목록 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_my_block(''00000000-0000-0000-0000-000000000072'',false)','42501'),'정지 계정 변경 차단');
rollback;
