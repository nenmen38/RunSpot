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
-- 작성 간격 제한을 건너뛰도록 테스트 글·댓글의 작성 시각을 과거로 옮깁니다.
create function pg_temp.age_board() returns void language sql security definer as $$
  update runspot_private.board_posts set created_at=created_at-interval '1 minute';
  update runspot_private.board_comments set created_at=created_at-interval '1 minute';
$$;
grant execute on function pg_temp.age_board() to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000161','reply161@example.com',now()),
 ('00000000-0000-0000-0000-000000000162','reply162@example.com',now()),
 ('00000000-0000-0000-0000-000000000163','reply163@example.com',now());
update public.profiles set nickname='답글검증'||right(id::text,3),visibility='public'
where id::text like '%00000000016_';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',true);
select public.create_board_post(gen_random_uuid(),'national','저녁 러닝 코스','한강에서 뛰어요','course');
select pg_temp.age_board();
select public.create_board_post(gen_random_uuid(),'national','맛집 추천','국수가 맛있어요 100%','food');
select pg_temp.age_board();
select public.create_board_post(gen_random_uuid(),'national','모닝 런','아침 RUNNING 기록','tip');
select (p->>'id') as post_id from jsonb_array_elements(public.board_feed('national')->'posts') p
where p->>'title'='저녁 러닝 코스' \gset

-- 제목·내용 검색은 대소문자를 구분하지 않고 %, _ 는 글자 그대로 찾습니다.
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national',search_text=>'러닝')->'posts')=1
  and (public.board_feed('national',search_text=>' 러닝 ')->'posts'->0->>'title')='저녁 러닝 코스','제목 검색');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national',search_text=>'running')->'posts')=1,'대소문자 무시 내용 검색');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national',search_text=>'100%')->'posts')=1
  and jsonb_array_length(public.board_feed('national',search_text=>'%')->'posts')=1
  and jsonb_array_length(public.board_feed('national',search_text=>'_')->'posts')=0,'특수 문자 그대로 검색');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national',search_text=>'  ')->'posts')=3,'빈 검색어는 전체');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national','food',search_text=>'러닝')->'posts')=0,'말머리와 함께 검색');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local',search_text=>'러닝')->'posts')=0,'다른 게시판 제외');
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''national'',search_text=>repeat(''가'',51))','22023'),'긴 검색어 거부');

-- 162가 댓글을 쓰고 163이 답글을 답니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select public.create_board_comment(gen_random_uuid(),:'post_id','같이 뛰어요') as parent_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000163',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''답글'',%L)',
  :'post_id','00000000-0000-0000-0000-00000000dead'),'P0001'),'없는 댓글에 답글 거부');
select public.create_board_comment(gen_random_uuid(),:'post_id','저도 갈래요 🙌',:'parent_id') as reply_id \gset
select pg_temp.assert_true((select c->>'parent_id'=:'parent_id' and c->>'body'='저도 갈래요 🙌'
  from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c where c->>'id'=:'reply_id'),'답글 조회');
select pg_temp.assert_true((select c->'parent_id'='null'::jsonb
  from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c where c->>'id'=:'parent_id'),'원댓글 표시');
select pg_temp.age_board();
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''답글의 답글'',%L)',
  :'post_id',:'reply_id'),'22023'),'답글의 답글 거부');

-- 다른 글의 댓글에는 답글을 달 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',true);
select (p->>'id') as other_post from jsonb_array_elements(public.board_feed('national')->'posts') p
where p->>'title'='맛집 추천' \gset
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''엉뚱한 답글'',%L)',
  :'other_post',:'parent_id'),'P0001'),'다른 글 댓글에 답글 거부');

-- 글 작성자는 댓글 알림 두 개, 원댓글 작성자는 답글 알림 하나를 받습니다.
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.my_notifications()) n
  where n->>'kind'='comment'),'글 작성자 댓글 알림');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select pg_temp.assert_true((select n->>'kind'='reply' and n->>'nickname'='답글검증163' and n->>'comment'='저도 갈래요 🙌'
  from (select public.my_notifications()->0 n) x) and jsonb_array_length(public.my_notifications())=1,'원댓글 작성자 답글 알림');

-- 글 작성자가 답글을 달면 원댓글 작성자만 알림을 받습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',true);
select public.create_board_comment(gen_random_uuid(),:'post_id','환영해요',:'parent_id');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.my_notifications())),'본인 답글은 알림 없음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select pg_temp.assert_true(jsonb_array_length(public.my_notifications())=2,'글 작성자 답글 알림');

-- 원댓글 작성자를 차단하면 그 아래 답글도 보이지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000163',true);
select public.change_my_block('00000000-0000-0000-0000-000000000162',true);
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=0,'차단 상대 댓글의 답글 숨김');
select public.change_my_block('00000000-0000-0000-0000-000000000162',false);

-- 원댓글을 지우면 답글과 그 알림도 함께 지워집니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select public.delete_board_comment(:'parent_id');
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=0
  and jsonb_array_length(public.my_notifications())=0,'원댓글 삭제 시 답글 정리');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.notifications),'답글 알림 정리');
rollback;
