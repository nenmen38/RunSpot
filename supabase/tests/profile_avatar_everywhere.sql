\set ON_ERROR_STOP on
begin;
create function pg_temp.check_face(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000991','face991@example.com',now()),
 ('00000000-0000-0000-0000-000000000992','face992@example.com',now()),
 ('00000000-0000-0000-0000-000000000993','face993@example.com',now());
-- 991은 큰 사진과 작은 사진을, 992는 큰 사진만(이전 앱) 저장합니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000991',true);
select public.set_my_avatar(encode('\xffd8aaaaffd9'::bytea,'base64'),encode('\xffd8bbffd9'::bytea,'base64'));
select pg_temp.check_face(pg_temp.fails($q$select public.set_my_avatar(encode('\xffd8ccffd9'::bytea,'base64'),'작은사진아님')$q$,'22023'),'작은 사진 형식 확인');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000992',true);
select public.set_my_avatar(encode('\xffd8ddddffd9'::bytea,'base64'));
reset role;
insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,title,body)
 values('00000000-0000-0000-0000-000000000994','00000000-0000-0000-0000-000000000991',gen_random_uuid(),'national','tip','사진 글','내용');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body)
 values('00000000-0000-0000-0000-000000000995','00000000-0000-0000-0000-000000000994','00000000-0000-0000-0000-000000000992',gen_random_uuid(),'댓글');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000993',true);
select public.profile_avatars(
  array['00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000992','00000000-0000-0000-0000-000000000993']::uuid[],
  array['00000000-0000-0000-0000-000000000994']::uuid[],
  array['00000000-0000-0000-0000-000000000995']::uuid[]) as faces \gset
select pg_temp.check_face(:'faces'::jsonb->'users'->'00000000-0000-0000-0000-000000000991'->>'photo'=encode('\xffd8bbffd9'::bytea,'base64'),'목록에는 작은 사진');
select pg_temp.check_face(:'faces'::jsonb->'users'->'00000000-0000-0000-0000-000000000992'->>'photo'=encode('\xffd8ddddffd9'::bytea,'base64'),'작은 사진이 없으면 큰 사진');
select pg_temp.check_face(not (:'faces'::jsonb->'users' ? '00000000-0000-0000-0000-000000000993'),'사진 없는 사람은 빠짐');
select pg_temp.check_face(:'faces'::jsonb->'posts'->'00000000-0000-0000-0000-000000000994'->>'photo'=encode('\xffd8bbffd9'::bytea,'base64'),'글쓴이 사진을 글 ID로');
select pg_temp.check_face(:'faces'::jsonb->'comments'->'00000000-0000-0000-0000-000000000995'->>'photo'=encode('\xffd8ddddffd9'::bytea,'base64'),'댓글 작성자 사진을 댓글 ID로');
select pg_temp.check_face(pg_temp.fails($q$select public.profile_avatars((select array_agg(gen_random_uuid()) from generate_series(1,101)))$q$,'22023'),'한 번에 100개까지');
-- 차단 관계면 사진이 보이지 않습니다.
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values('00000000-0000-0000-0000-000000000991','00000000-0000-0000-0000-000000000993');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000993',true);
select public.profile_avatars(array['00000000-0000-0000-0000-000000000991']::uuid[],
  array['00000000-0000-0000-0000-000000000994']::uuid[]) as hidden \gset
select pg_temp.check_face(:'hidden'::jsonb->'users'='{}'::jsonb and :'hidden'::jsonb->'posts'='{}'::jsonb,'차단 관계면 숨김');
rollback;
