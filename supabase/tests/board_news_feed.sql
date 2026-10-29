\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.titles(feed jsonb) returns text[] language sql as $$
  select coalesce(array_agg(p->>'title' order by p->>'title'),'{}') from jsonb_array_elements(feed->'posts') p;
$$;
create function pg_temp.age_board() returns void language sql security definer as $$
  update runspot_private.board_posts set created_at=created_at-interval '1 minute';
$$;
grant execute on function pg_temp.age_board(),pg_temp.titles(jsonb) to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000181','news181@example.com',now()),
 ('00000000-0000-0000-0000-000000000182','news182@example.com',now());
update public.profiles set nickname='소식검증'||right(id::text,3),visibility='public'
where id::text like '%00000000018_';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select public.set_my_board_region('부산광역시 해운대구');
select public.create_board_post(gen_random_uuid(),'local','해운대 코스','바닷가','course');
select pg_temp.age_board();
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select public.set_my_board_region('서울특별시 마포구');
select public.create_board_post(gen_random_uuid(),'national','전국 꿀팁','물 챙기기','tip');
select pg_temp.age_board();
select public.create_board_post(gen_random_uuid(),'local','망원 코스','한강','course');
select pg_temp.age_board();
select public.create_board_post(gen_random_uuid(),'local','망원 맛집','국수','food');

-- 러닝 소식은 전국 글과 내 동네 글을 함께 최신순으로 보여주고 다른 동네 글은 빠집니다.
select pg_temp.assert_true((select array_agg(p->>'title') from jsonb_array_elements(public.board_feed('news')->'posts') p)
  =array['망원 맛집','망원 코스','전국 꿀팁'],'러닝 소식 최신순');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('news','course'))=array['망원 코스'],'러닝 소식 말머리');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('news',search_text=>'꿀팁'))=array['전국 꿀팁'],'러닝 소식 검색');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('local'))=array['망원 맛집','망원 코스'],'동네 글만');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('national'))=array['전국 꿀팁'],'이전 앱 전국 게시판 유지');

-- 동네를 바꾸면 그 동네 글이 보입니다.
select public.set_my_board_region('부산광역시 해운대구');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('local'))=array['해운대 코스'],'바꾼 동네 글');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('news'))=array['전국 꿀팁','해운대 코스'],'바꾼 동네가 러닝 소식에 반영');
select pg_temp.assert_true(pg_temp.titles(public.board_feed('race'))='{}','대회 게시판 분리');

-- 동네를 정하지 않으면 러닝 소식에는 전국 글만 보입니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
reset role;
delete from runspot_private.board_regions where user_id='00000000-0000-0000-0000-000000000182';
set local role authenticated;
select pg_temp.assert_true(pg_temp.titles(public.board_feed('news'))=array['전국 꿀팁'],'동네 미설정 시 전국 글만');
rollback;
