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
 ('00000000-0000-0000-0000-000000000141','engage141@example.com',now()),
 ('00000000-0000-0000-0000-000000000142','engage142@example.com',now()),
 ('00000000-0000-0000-0000-000000000143','engage143@example.com',now()),
 ('00000000-0000-0000-0000-000000000144','engage144@example.com',null),
 ('00000000-0000-0000-0000-000000000145','engage145@example.com',now());
update public.profiles set nickname='반응검증'||right(id::text,3),visibility='public'
where id::text like '%00000000014_' and id<>'00000000-0000-0000-0000-000000000144';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000145','admin');
\set img1 '00000000-0000-0000-0000-000000000141/11111111-1111-4111-8111-111111111111.jpg'
\set img2 '00000000-0000-0000-0000-000000000141/22222222-2222-4222-8222-222222222222.jpg'
\set other '00000000-0000-0000-0000-000000000142/33333333-3333-4333-8333-333333333333.jpg'

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
select public.set_my_board_region('서울특별시 마포구');
-- 사진은 본인 폴더의 무작위 JPEG 이름만 올릴 수 있습니다.
insert into storage.objects(bucket_id,name) values('board-images',:'img1'),('board-images',:'img2');
select pg_temp.assert_true(pg_temp.fails(format('insert into storage.objects(bucket_id,name) values(''board-images'',%L)',:'other'),'42501'),'타인 폴더 업로드 거부');
select pg_temp.assert_true(pg_temp.fails('insert into storage.objects(bucket_id,name) values(''board-images'',''00000000-0000-0000-0000-000000000141/photo.png'')','42501'),'형식이 다른 파일 이름 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'',requested_images=>array[%L])',:'other'),'22023'),'타인 사진 첨부 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'',requested_images=>array[%L,%L,%L,%L,%L])',
  :'img1',:'img2',:'img1',:'img2',:'img1'),'22023'),'사진 5장 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_post(gen_random_uuid(),''national'',''제목'',''내용'',''tip'',requested_images=>array[%L,%L])',
  :'img1',:'img1'),'22023'),'같은 사진 중복 거부');
select public.create_board_post('00000000-0000-0000-0000-00000000c141','local','망원 한강 코스 🏃‍♂️','노을이 예뻐요 🌇',
  'course',requested_images=>array[:'img1',:'img2']);
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->>'title')='망원 한강 코스 🏃‍♂️'
  and (public.board_feed('local')->'posts'->0->'images')=to_jsonb(array[:'img1',:'img2']),'이모지와 사진 경로 저장');
reset role;
select id as post_id from runspot_private.board_posts where client_post_id='00000000-0000-0000-0000-00000000c141' \gset
set local role authenticated;

-- 다른 동네 주민은 동네 글과 사진에 접근하지 못합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000143',true);
select public.set_my_board_region('부산광역시 해운대구');
select pg_temp.assert_true((select count(*)=0 from storage.objects where name=:'img1'),'다른 동네 사진 조회 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.set_board_like(%L,true)',:'post_id'),'P0001'),'다른 동네 글 좋아요 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.board_comments(%L)',:'post_id'),'P0001'),'다른 동네 댓글 조회 거부');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',true);
select public.set_my_board_region('서울특별시 마포구');
select pg_temp.assert_true((select count(*)=1 from storage.objects where name=:'img1'),'같은 동네 주민 사진 조회');
delete from storage.objects where name=:'img1';
select pg_temp.assert_true((select count(*)=1 from storage.objects where name=:'img1'),'타인 사진 삭제 불가');
select pg_temp.assert_true((public.set_board_like(:'post_id',true)->>'like_count')::int=1,'좋아요');
select pg_temp.assert_true((public.set_board_like(:'post_id',true)->>'like_count')::int=1,'좋아요 멱등성');
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->>'liked')::boolean
  and (public.board_feed('local')->'posts'->0->>'like_count')::int=1,'목록 좋아요 표시');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''  '')',:'post_id'),'22023'),'빈 댓글 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,repeat(''가'',501))',:'post_id'),'22023'),'긴 댓글 거부');
select public.create_board_comment('00000000-0000-0000-0000-00000000d142',:'post_id',' 저도 가볼게요 👍 ');
select pg_temp.assert_true(public.create_board_comment('00000000-0000-0000-0000-00000000d142',:'post_id','다른 내용')=
  public.create_board_comment('00000000-0000-0000-0000-00000000d142',:'post_id','또 다른 내용'),'댓글 재전송 중복 방지');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''연속'')',:'post_id'),'P0001'),'댓글 작성 간격');
select pg_temp.assert_true((public.board_comments(:'post_id')->'comments'->0->>'body')='저도 가볼게요 👍'
  and jsonb_array_length(public.board_comments(:'post_id')->'comments')=1,'댓글 조회와 공백 정리');
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,(select (public.board_feed(''local'')->''posts''->0->>''updated_at'')::timestamptz),''tip'',''제목'',''내용'',null,null,null)',:'post_id'),'42501'),'타인 글 수정 거부');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000144',true);
select public.set_my_board_region('서울특별시 마포구');
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=1
  and not (public.board_comments(:'post_id')->>'can_write')::boolean,'미인증 사용자 댓글 읽기만 가능');
select pg_temp.assert_true(pg_temp.fails(format('select public.set_board_like(%L,true)',:'post_id'),'42501'),'미인증 좋아요 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_board_comment(gen_random_uuid(),%L,''댓글'')',:'post_id'),'42501'),'미인증 댓글 거부');
select pg_temp.assert_true(pg_temp.fails('insert into storage.objects(bucket_id,name) values(''board-images'',''00000000-0000-0000-0000-000000000144/44444444-4444-4444-8444-444444444444.jpg'')','42501'),'미인증 업로드 거부');

-- 작성자는 말머리·내용·사진을 고칠 수 있고 게시판 종류와 동네는 그대로 남습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,(select (public.board_feed(''local'')->''posts''->0->>''updated_at'')::timestamptz),null,''제목'',''내용'',null,null,null)',:'post_id'),'22023'),'수정 시 말머리 필요');
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,(select (public.board_feed(''local'')->''posts''->0->>''updated_at'')::timestamptz),''tip'',''제목'',''내용'',current_date,null,null)',:'post_id'),'22023'),'일반 글에 대회 정보 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,now()-interval ''1 day'',''food'',''제목'',''내용'',null,null,null,array[%L])',
  :'post_id',:'img2'),'P0001'),'오래된 화면의 사진 수정 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,(select (public.board_feed(''local'')->''posts''->0->>''updated_at'')::timestamptz),''food'',''제목'',''내용'',null,null,null,array[%L])',
  :'post_id',:'other'),'22023'),'타인 사진으로 수정 거부');
select (public.board_feed('local')->'posts'->0->>'updated_at')::timestamptz as before_edit \gset
select public.update_my_board_post(:'post_id',:'before_edit','food',' 망원 맛집 정리 ','국수 🍜',null,null,null,array[:'img2']);

select pg_temp.assert_true((select p->>'topic'='food' and p->>'title'='망원 맛집 정리'
  and (p->>'updated_at')::timestamptz > (p->>'created_at')::timestamptz
  and p->'images'=to_jsonb(array[:'img2']) and p->>'board'='local' and p->>'region'='서울특별시 마포구'
  from (select public.board_feed('local')->'posts'->0 p) x),'글 수정');
select pg_temp.assert_true(jsonb_array_length(public.board_feed('local','food')->'posts')=1,'수정한 말머리로 필터');
-- 사진을 보내지 않는 이전 앱의 수정은 기존 사진을 유지합니다.
select public.update_my_board_post(:'post_id',(public.board_feed('local')->'posts'->0->>'updated_at')::timestamptz,
  'food','망원 맛집 정리','국수 🍜 맛있어요',null,null,null);
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->'images')=to_jsonb(array[:'img2']),'사진 없이 수정하면 사진 유지');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where name=:'img1'),'글에서 뺀 사진 조회 거부');
select pg_temp.assert_true((select count(*)=1 from storage.objects where name=:'img2'),'남은 사진 조회');

-- 차단하면 서로의 좋아요·댓글이 집계와 목록에서 빠집니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
select public.change_my_block('00000000-0000-0000-0000-000000000142',true);
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->>'like_count')::int=0
  and (public.board_feed('local')->'posts'->0->>'comment_count')::int=0,'차단 상대 반응 제외');
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=0,'차단 상대 댓글 숨김');
select public.change_my_block('00000000-0000-0000-0000-000000000142',false);
select pg_temp.assert_true((public.board_feed('local')->'posts'->0->>'comment_count')::int=1,'차단 해제 후 댓글 집계');
select pg_temp.assert_true(pg_temp.fails(format('select public.delete_board_comment(%L)',
  (select public.board_comments(:'post_id')->'comments'->0->>'id')),'42501'),'타인 댓글 삭제 거부');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',true);
select pg_temp.assert_true((public.set_board_like(:'post_id',false)->>'like_count')::int=0,'좋아요 취소');
select pg_temp.assert_true((public.set_board_like(:'post_id',false)->>'like_count')::int=0,'좋아요 취소 멱등성');
select pg_temp.age_board();
select public.create_board_comment(gen_random_uuid(),:'post_id','두 번째 댓글');
select public.delete_board_comment((select (public.board_comments(:'post_id')->'comments'->0->>'id')::uuid));
select public.delete_board_comment('00000000-0000-0000-0000-00000000dead');
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=1
  and (public.board_comments(:'post_id')->'comments'->0->>'body')='두 번째 댓글','본인 댓글 삭제');

-- 관리자는 타인 댓글을 지울 수 있고 감사 기록을 남깁니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000145',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select public.set_my_board_region('서울특별시 마포구');
select pg_temp.assert_true((public.board_comments(:'post_id')->>'can_moderate')::boolean,'관리자 권한 표시');
select public.delete_board_comment((select (public.board_comments(:'post_id')->'comments'->0->>'id')::uuid));
select pg_temp.assert_true(jsonb_array_length(public.board_comments(:'post_id')->'comments')=0,'관리자 댓글 삭제');
reset role;
select pg_temp.assert_true(exists(select 1 from runspot_private.audit_logs where action='board_comment_delete'),'댓글 삭제 감사 기록');
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_comments','42501'),'댓글 원본 접근 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_likes','42501'),'좋아요 원본 접근 거부');

-- 글을 지우면 좋아요·댓글이 함께 지워지고 사진은 더 이상 다른 사람이 볼 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
select public.delete_board_post(:'post_id');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.board_comments where post_id=:'post_id')
  and (select count(*)=0 from runspot_private.board_likes where post_id=:'post_id'),'글 삭제 시 반응 정리');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000142',true);
select pg_temp.assert_true((select count(*)=0 from storage.objects where name=:'img2'),'삭제한 글 사진 조회 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
select pg_temp.assert_true((select count(*)=2 from storage.objects where bucket_id='board-images'),'작성자는 본인 사진 조회');
delete from storage.objects where name in (:'img1',:'img2');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='board-images'),'작성자 사진 삭제');
rollback;
