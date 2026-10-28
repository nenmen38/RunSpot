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
 ('00000000-0000-0000-0000-000000000151','delete151@example.com',now()),
 ('00000000-0000-0000-0000-000000000152','delete152@example.com',now());
update public.profiles set nickname='탈퇴검증'||right(id::text,3),visibility='public'
where id::text like '%00000000015_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000152','00000000-0000-0000-0000-000000000151','accepted');
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000151','moderator');

set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.delete_my_account()','42501'),'비로그인 탈퇴 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
-- 기록·게시글·좋아요·댓글을 남긴 뒤 탈퇴합니다.
reset role;
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
values('00000000-0000-0000-0000-000000000151',gen_random_uuid(),now()-interval '40 minutes',now()-interval '10 minutes',5000,1800);
set local role authenticated;
select public.set_my_board_region('서울특별시 종로구');
select public.create_board_post('00000000-0000-0000-0000-00000000e151','national','탈퇴 전 글','내용','tip') as post_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select public.set_board_like(:'post_id',true);
select public.create_board_comment(gen_random_uuid(),:'post_id','댓글');
select public.create_board_post(gen_random_uuid(),'national','남는 글','내용','tip') as other_post \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select public.set_board_like(:'other_post',true);
select public.create_board_comment(gen_random_uuid(),:'other_post','탈퇴할 사람의 댓글');
select public.delete_my_account();
reset role;
select pg_temp.assert_true(not exists(select 1 from auth.users where id='00000000-0000-0000-0000-000000000151'),'인증 계정 삭제');
select pg_temp.assert_true(not exists(select 1 from public.profiles where id='00000000-0000-0000-0000-000000000151'),'프로필 삭제');
select pg_temp.assert_true(not exists(select 1 from public.runs where user_id='00000000-0000-0000-0000-000000000151'),'러닝 기록 삭제');
select pg_temp.assert_true(not exists(select 1 from public.friendships where '00000000-0000-0000-0000-000000000151' in (user_low,user_high)),'친구 관계 삭제');
select pg_temp.assert_true(not exists(select 1 from runspot_private.user_roles where user_id='00000000-0000-0000-0000-000000000151'),'역할 삭제');
select pg_temp.assert_true(not exists(select 1 from runspot_private.board_posts where author_id='00000000-0000-0000-0000-000000000151'),'게시글 삭제');
select pg_temp.assert_true(not exists(select 1 from runspot_private.board_likes where user_id='00000000-0000-0000-0000-000000000151')
  and not exists(select 1 from runspot_private.board_comments where author_id='00000000-0000-0000-0000-000000000151'),'좋아요·댓글 삭제');
select pg_temp.assert_true(exists(select 1 from runspot_private.board_posts where id=:'other_post'),'다른 사람 글 유지');
select pg_temp.assert_true(exists(select 1 from runspot_private.audit_logs where action='account_delete'
  and target_id='00000000-0000-0000-0000-000000000151' and actor_id is null),'탈퇴 감사 기록 보존');
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.delete_my_account()','42501'),'이미 삭제된 계정 재요청 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select pg_temp.assert_true(exists(select 1 from public.profiles where id='00000000-0000-0000-0000-000000000152'),'다른 사용자 유지');
select pg_temp.assert_true((public.board_feed('national')->'posts'->0->>'like_count')::int=0
  and (public.board_feed('national')->'posts'->0->>'comment_count')::int=0,'탈퇴한 사람 반응 집계 제외');
rollback;
