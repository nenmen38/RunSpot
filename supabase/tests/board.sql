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
-- 30초 작성 간격을 건너뛰도록 테스트 글의 작성 시각을 과거로 옮깁니다.
create function pg_temp.age_posts() returns void language sql security definer as $$
  update runspot_private.board_posts set created_at=created_at-interval '1 minute';
$$;
grant execute on function pg_temp.age_posts() to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000131','board131@example.com',now()),
 ('00000000-0000-0000-0000-000000000132','board132@example.com',now()),
 ('00000000-0000-0000-0000-000000000133','board133@example.com',now()),
 ('00000000-0000-0000-0000-000000000134','board134@example.com',null),
 ('00000000-0000-0000-0000-000000000135','board135@example.com',now());
update public.profiles set nickname='게시판검증'||right(id::text,3),visibility='public'
where id::text like '%00000000013_' and id<>'00000000-0000-0000-0000-000000000134';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000135','admin');

set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''national'')','42501'),'비로그인 조회 거부');
select pg_temp.assert_true(pg_temp.fails('select public.set_my_board_region(''서울특별시 강남구'')','42501'),'비로그인 동네 설정 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_posts','42501'),'게시글 원본 접근 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_regions','42501'),'동네 원본 접근 거부');
select pg_temp.assert_true(public.my_board_region() is null,'동네 미설정');
select pg_temp.assert_true((public.board_feed('local')->'posts')='[]'::jsonb and public.board_feed('local')->>'region' is null,'동네 미설정 시 빈 목록');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''local'',''제목'',''내용'',''course'')','22023'),'동네 미설정 작성 거부');
select pg_temp.assert_true(pg_temp.fails('select public.set_my_board_region(''Seoul'')','22023'),'잘못된 동네 거부');
select pg_temp.assert_true(public.set_my_board_region(' 서울특별시 강남구 ')='서울특별시 강남구','동네 설정');
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''free'')','22023'),'없는 게시판 거부');
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''race'',''food'')','22023'),'대회 말머리 거부');
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''national'',null,now(),null)','22023'),'불완전한 페이지 기준 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''local'',''제목'',''내용'')','22023'),'말머리 없는 글 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''local'',''  '',''내용'',''tip'')','22023'),'빈 제목 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제목'',repeat(''가'',2001),''tip'')','22023'),'긴 내용 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'',current_date)','22023'),'일반 글의 대회 정보 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''race'',''대회'',''내용'',null,current_date,''여의도'')','42501'),'일반 사용자 대회 공지 거부');
select pg_temp.assert_true(public.create_board_post('00000000-0000-0000-0000-00000000a131','local',' 양재천 야간 코스 ','가로등이 밝아요','course')=
  public.create_board_post('00000000-0000-0000-0000-00000000a131','local','다른 제목','다른 내용','tip'),'재전송 중복 방지');
reset role;
select pg_temp.assert_true((select count(*)=1 and min(title)='양재천 야간 코스' from runspot_private.board_posts),'재전송 시 첫 글 하나만 저장');
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''food'')','P0001'),'30초 작성 간격');
select pg_temp.age_posts();
select public.create_board_post(gen_random_uuid(),'national','전국 맛집','국밥','food');
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->>'title')='양재천 야간 코스'
  and (public.board_feed('local')->'posts'->0->>'is_mine')::boolean,'동네 글 조회와 제목 정리');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local','food')->'posts')=0,'말머리 필터');
select pg_temp.assert_true((public.board_feed('local')->>'can_write')::boolean
  and not (public.board_feed('local')->>'can_post_race')::boolean,'일반 사용자 권한 표시');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000132',true);
select public.set_my_board_region('서울특별시 강남구');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=1
  and not (public.board_feed('local')->'posts'->0->>'is_mine')::boolean,'같은 동네 주민 조회');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000133',true);
select public.set_my_board_region('부산광역시 해운대구');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=0,'다른 동네 글 제외');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national')->'posts')=1,'전국 글은 모두 조회');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000134',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national')->'posts')=1
  and not (public.board_feed('national')->>'can_write')::boolean,'미인증 사용자는 읽기만 가능');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'')','42501'),'미인증 작성 거부');

-- 동네를 바꿔도 이미 쓴 글은 작성 당시 동네에 남습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select public.set_my_board_region('부산광역시 해운대구');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=0,'동네 변경 후 이전 동네 글 제외');
select public.set_my_board_region('서울특별시 강남구');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000132',true);
select public.change_my_block('00000000-0000-0000-0000-000000000131',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=0,'차단한 작성자 글 제외');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=1,'본인 글은 차단과 무관하게 조회');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000132',true);
select public.change_my_block('00000000-0000-0000-0000-000000000131',false);
select pg_temp.assert_true(pg_temp.fails(format('select public.delete_board_post(%L)',
  (select (public.board_feed('local')->'posts'->0->>'id'))),'42501'),'타인 글 삭제 거부');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000135',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''race'',''대회'',''내용'',null,current_date,''여의도'')','42501'),'다중 인증 없는 대회 공지 거부');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true((public.board_feed('race')->>'can_post_race')::boolean,'관리자 대회 공지 권한 표시');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''race'',''대회'',''내용'',null,current_date,''여의도'',''http://a.kr'')','22023'),'https가 아닌 링크 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''race'',''대회'',''내용'',''tip'',current_date,''여의도'')','22023'),'대회 공지 말머리 거부');
select public.create_board_post(gen_random_uuid(),'race','서울 하프 마라톤','접수 중',null,
  ((now() at time zone 'Asia/Seoul')::date + 30),'광화문','https://example.com/race');
select pg_temp.age_posts();
select public.create_board_post(gen_random_uuid(),'race','오늘 대회','당일',null,
  (now() at time zone 'Asia/Seoul')::date,'여의도');
reset role;
insert into runspot_private.board_posts(author_id,client_post_id,board,title,body,race_date,race_place)
values('00000000-0000-0000-0000-000000000135',gen_random_uuid(),'race','지난 대회','종료',current_date-1,'부산');
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.board_feed('race')->'posts')=2
  and (public.board_feed('race')->'posts'->0->>'title')='오늘 대회','지난 대회 제외와 날짜순 정렬');
select pg_temp.assert_true(public.board_feed('race')->'next'='null'::jsonb,'대회 공지 다음 페이지 없음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000134',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('race')->'posts')=2,'미인증 사용자 대회 공지 조회');

-- 관리자는 다른 사용자의 글을 삭제할 수 있고 감사 기록을 남깁니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000135',true);
select public.delete_board_post((select (x->>'id')::uuid from jsonb_array_elements(public.board_feed('national')->'posts') x limit 1));
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national')->'posts')=0,'관리자 삭제');
reset role;
select pg_temp.assert_true(exists(select 1 from runspot_private.audit_logs where action='board_post_delete'
  and actor_id='00000000-0000-0000-0000-000000000135'),'관리자 삭제 감사 기록');

-- 21개 이상이면 20개씩 나누고 다음 기준으로 이어서 조회합니다.
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body,created_at)
select '00000000-0000-0000-0000-000000000132',gen_random_uuid(),'national','tip','글'||i,'내용',now()-make_interval(mins=>i)
from generate_series(1,25) i;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000133',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national')->'posts')=20
  and public.board_feed('national')->'next' <> 'null'::jsonb,'첫 페이지 20개');
select pg_temp.assert_true((select jsonb_array_length(public.board_feed('national',null,
  (f->'next'->>'at')::timestamptz,(f->'next'->>'id')::uuid)->'posts')=5
  from (select public.board_feed('national') f) page),'다음 페이지 나머지');
select pg_temp.assert_true((select (public.board_feed('national',null,
  (f->'next'->>'at')::timestamptz,(f->'next'->>'id')::uuid)->'posts'->0->>'title')='글21'
  from (select public.board_feed('national') f) page),'페이지 경계 중복 없음');

-- 하루 20개 작성 한도.
reset role;
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body,created_at)
select '00000000-0000-0000-0000-000000000133',gen_random_uuid(),'national','tip','한도'||i,'내용',now()-interval '2 hours'
from generate_series(1,20) i;
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'')','P0001'),'하루 작성 한도');

-- 본인 글 삭제는 재요청해도 무해합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
select public.delete_board_post((select (public.board_feed('local')->'posts'->0->>'id')::uuid));
select public.delete_board_post('00000000-0000-0000-0000-00000000dead');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local')->'posts')=0,'본인 글 삭제');

-- 정지된 작성자의 글은 숨기고 정지 계정은 조회할 수 없습니다.
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000132';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000133',true);
select pg_temp.assert_true(jsonb_array_length(public.board_feed('national')->'posts')=20
  and not exists(select 1 from jsonb_array_elements(public.board_feed('national')->'posts') x where x->>'title' like '글%'),'정지 작성자 글 숨김');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000132',true);
select pg_temp.assert_true(pg_temp.fails('select public.board_feed(''national'')','42501'),'정지 계정 조회 거부');
rollback;
