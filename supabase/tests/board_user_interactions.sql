\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return true; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000991','menu991@example.com',now()),
 ('00000000-0000-0000-0000-000000000992','menu992@example.com',now()),
 ('00000000-0000-0000-0000-000000000993','menu993@example.com',now());
update public.profiles set nickname='상호작용'||right(id::text,3) where id::text like '%00000000099_';
insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,title,body) values
 ('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000992',gen_random_uuid(),'national','tip','공개 글','본문');
insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,region,title,body) values
 ('00000000-0000-0000-0000-000000000992','00000000-0000-0000-0000-000000000993',gen_random_uuid(),'local','tip','서울특별시 강남구','다른 동네 글','본문');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body) values
 ('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000993',gen_random_uuid(),'댓글');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.board_user_interaction(''00000000-0000-0000-0000-000000000991'')'),'비로그인 접근 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000991',true);
select pg_temp.assert_true(public.board_user_interaction('00000000-0000-0000-0000-000000000991')->>'user_id'='00000000-0000-0000-0000-000000000992','비공개 프로필 작성자도 보이는 글에서 식별');
reset role;
update public.profiles set visibility='friends' where id in ('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000992');
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000992','00000000-0000-0000-0000-000000000991','accepted');
select pg_temp.assert_true(runspot_private.can_view_location('00000000-0000-0000-0000-000000000992'),'친구 공개 러너는 차단 전 친구에게 위치 공개');
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.board_user_interaction(''00000000-0000-0000-0000-000000000992'')'),'다른 동네 글의 작성자 조회 거부');
select pg_temp.assert_true(pg_temp.fails('select public.board_user_interaction(''00000000-0000-0000-0000-000000000992'',''00000000-0000-0000-0000-000000000991'')'),'다른 글 댓글 조합 거부');
select public.board_user_interaction('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000991','block');
select pg_temp.assert_true((select count(*)=1 from public.my_blocks()),'댓글 작성자 차단');
select public.board_user_interaction('00000000-0000-0000-0000-000000000991',null,'block');
select pg_temp.assert_true((select count(*)=2 from public.my_blocks()),'글 작성자 차단');
select pg_temp.assert_true(pg_temp.fails('select public.board_user_interaction(''00000000-0000-0000-0000-000000000991'')'),'차단 후 글 재조회 거부');
reset role;
select pg_temp.assert_true(not runspot_private.can_view_location('00000000-0000-0000-0000-000000000992'),'차단 후 상대 위치 비공개');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000992',true);
select pg_temp.assert_true(not runspot_private.can_view_location('00000000-0000-0000-0000-000000000991'),'상대에게도 내 위치 비공개');
rollback;
