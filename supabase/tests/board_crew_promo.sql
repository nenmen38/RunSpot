\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000241','promo241@example.com',now()),
 ('00000000-0000-0000-0000-000000000242','promo242@example.com',now()),
 ('00000000-0000-0000-0000-000000000243','promo243@example.com',now());
update public.profiles set nickname='홍보검증'||right(id::text,3),visibility='public' where id::text like '%00000000024_';
insert into runspot_private.crews(owner_id,name,icon) values
 ('00000000-0000-0000-0000-000000000241','한강러너스','wave');
select id as crew from runspot_private.crews where name='한강러너스' \gset

set local role authenticated;
-- 크루장은 자기 크루를 골라 홍보글을 쓰고, 글에 크루 이름·아이콘이 붙습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000241',true);
select pg_temp.assert_true((select jsonb_array_length(f->'own_crews')=1 and f->'own_crews'->0->>'name'='한강러너스'
  from (select public.board_feed('crew') f) x),'크루장 크루 목록');
select pg_temp.assert_true(pg_temp.fails(format(
  'select public.create_board_post(gen_random_uuid(),''crew'',''모집'',''내용'',''free'',requested_crew=>%L)',:'crew'),'22023'),
  '크루 홍보 말머리 거부');
select pg_temp.assert_true(pg_temp.fails(
  'select public.create_board_post(gen_random_uuid(),''crew'',''모집'',''내용'')','42501'),'크루 없는 홍보글 거부');
select public.create_board_post(gen_random_uuid(),'crew','한강러너스 크루원 모집','매주 토요일 7시',requested_crew=>:'crew');
select pg_temp.assert_true((select jsonb_array_length(f->'posts')=1 and f->'posts'->0->'crew'->>'name'='한강러너스'
  and f->'posts'->0->'crew'->>'icon'='wave' and f->'posts'->0->>'topic' is null
  from (select public.board_feed('crew') f) x),'크루 홍보 목록');
select pg_temp.assert_true((select jsonb_array_length(public.board_feed('news')->'posts')=0),'러닝 소식에 홍보글 제외');
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''crew'',''free'')','22023'),'크루 홍보 말머리 조회 거부');

-- 크루장이 아니면 홍보글을 쓸 수 없고, 일반 글에는 크루를 붙일 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000242',true);
select pg_temp.assert_true((select jsonb_array_length(public.board_feed('crew')->'own_crews')=0),'크루장 아님');
select pg_temp.assert_true(pg_temp.fails(format(
  'select public.create_board_post(gen_random_uuid(),''crew'',''모집'',''내용'',requested_crew=>%L)',:'crew'),'42501'),
  '남의 크루 홍보 거부');
select pg_temp.assert_true(pg_temp.fails(format(
  'select public.create_board_post(gen_random_uuid(),''national'',''글'',''내용'',''free'',requested_crew=>%L)',:'crew'),'22023'),
  '일반 글 크루 지정 거부');
-- 새 말머리 '자유'·'질문'과 이전 앱 형식 호출(requested_crew 없음)
select public.create_board_post(gen_random_uuid(),'national','자유 글','안녕하세요','free');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000243',true);
select public.create_board_post(gen_random_uuid(),'national','질문 글','신발 추천해 주세요','question');
select pg_temp.assert_true((select array_agg(p->>'title')=array['질문 글']
  from jsonb_array_elements(public.board_feed('news','question')->'posts') p),'질문 말머리 조회');
select pg_temp.assert_true((select array_agg(p->>'title')=array['자유 글']
  from jsonb_array_elements(public.board_feed('news','free')->'posts') p),'자유 말머리 조회');
select pg_temp.assert_true(pg_temp.fails(
  'select public.create_board_post(gen_random_uuid(),''national'',''글'',''내용'',''chat'')','22023'),'없는 말머리 거부');

-- 크루장은 홍보글을 말머리 없이 수정할 수 있습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000241',true);
select (public.board_feed('crew')->'posts'->0) as promo \gset
select public.update_my_board_post((:'promo'::jsonb->>'id')::uuid,(:'promo'::jsonb->>'updated_at')::timestamptz,null,
  '한강러너스 모집 (수정)','매주 토요일 7시',null,null,null);
select pg_temp.assert_true((select f->'posts'->0->>'title'='한강러너스 모집 (수정)'
  and f->'posts'->0->'crew'->>'name'='한강러너스' from (select public.board_feed('crew') f) x),'홍보글 수정');
reset role;
-- 크루가 없어지면 홍보글도 함께 지웁니다.
delete from runspot_private.crews where id=:'crew';
select pg_temp.assert_true(not exists(select 1 from runspot_private.board_posts where board='crew'),'크루 삭제 시 홍보글 삭제');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''crew'')','42501'),'익명 조회 거부');
rollback;
