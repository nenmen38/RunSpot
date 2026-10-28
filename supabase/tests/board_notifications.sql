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
create function pg_temp.age_board() returns void language sql security definer as $$
  update runspot_private.board_posts set created_at=created_at-interval '1 minute';
  update runspot_private.board_comments set created_at=created_at-interval '1 minute';
$$;
grant execute on function pg_temp.age_board() to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000151','notify151@example.com',now()),
 ('00000000-0000-0000-0000-000000000152','notify152@example.com',now()),
 ('00000000-0000-0000-0000-000000000153','notify153@example.com',now());
update public.profiles set nickname='알림검증'||right(id::text,3),visibility='public'
where id::text like '%00000000015_';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select public.create_board_post('00000000-0000-0000-0000-00000000c151','national','한강 코스','좋아요','course');
select (public.board_feed('national')->'posts'->0->>'id') as post_id \gset
-- 내 글에 내가 남긴 반응은 알림이 되지 않습니다.
select public.set_board_like(:'post_id',true);
select public.create_board_comment(gen_random_uuid(),:'post_id','제 글이에요');
select pg_temp.assert_true(public.unread_notification_count()=0
  and jsonb_array_length(public.my_notifications())=0,'본인 반응 알림 제외');
select pg_temp.assert_true((public.board_post(:'post_id')->'posts'->0->>'title')='한강 코스'
  and (public.board_post(:'post_id')->>'can_write')::boolean,'글 하나 조회');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select public.set_board_like(:'post_id',true);
select public.create_board_comment(gen_random_uuid(),:'post_id',' 같이 뛰어요 🏃 ');
select pg_temp.assert_true(public.unread_notification_count()=0,'다른 사람 알림은 보이지 않음');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select pg_temp.assert_true(public.unread_notification_count()=2,'좋아요·댓글 알림 수');
select pg_temp.assert_true((select c->>'comment'='같이 뛰어요 🏃' and c->>'nickname'='알림검증152'
  and c->>'post_title'='한강 코스' and c->>'post_id'=:'post_id' and not (c->>'read')::boolean
  and l->'comment'='null'::jsonb and l->>'nickname'='알림검증152'
  from (select (select x from jsonb_array_elements(n) x where x->>'kind'='comment') c,
    (select x from jsonb_array_elements(n) x where x->>'kind'='like') l
    from (select public.my_notifications() n) y) z),'알림 목록 내용');

-- 좋아요를 취소하면 알림이 숨고, 다시 눌러도 알림이 두 번 생기지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select public.set_board_like(:'post_id',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select pg_temp.assert_true(public.unread_notification_count()=1,'좋아요 취소 시 알림 숨김');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select public.set_board_like(:'post_id',true);
reset role;
select pg_temp.assert_true((select count(*)=1 from runspot_private.notifications where kind='like'),'좋아요 알림 중복 방지');
set local role authenticated;

-- 화면에 보여준 시각까지만 읽음 처리합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select pg_temp.assert_true(pg_temp.fails('select public.mark_notifications_read(null)','22023'),'읽음 시각 필요');
select public.mark_notifications_read(now()-interval '1 hour');
select pg_temp.assert_true(public.unread_notification_count()=2,'이후 알림은 읽지 않음 유지');
select public.mark_notifications_read(now());
select pg_temp.assert_true(public.unread_notification_count()=0
  and (public.my_notifications()->0->>'read')::boolean,'읽음 처리');

-- 차단한 사용자의 알림은 보이지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',true);
select public.create_board_comment(gen_random_uuid(),:'post_id','저도요');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select pg_temp.assert_true(public.unread_notification_count()=1,'새 댓글 알림');
select public.change_my_block('00000000-0000-0000-0000-000000000153',true);
select pg_temp.assert_true(public.unread_notification_count()=0
  and jsonb_array_length(public.my_notifications())=2,'차단 상대 알림 숨김');
select public.change_my_block('00000000-0000-0000-0000-000000000153',false);

-- 댓글을 지우면 그 댓글 알림도 지워집니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',true);
select public.delete_board_comment((select (c->>'id')::uuid from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c
  where c->>'body'='저도요'));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select pg_temp.assert_true(public.unread_notification_count()=0
  and jsonb_array_length(public.my_notifications())=2,'삭제한 댓글 알림 정리');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.notifications','42501'),'알림 원본 접근 거부');
select pg_temp.assert_true(pg_temp.fails('select public.board_post(''00000000-0000-0000-0000-00000000dead'')','P0001'),'없는 글 조회 거부');

-- 글을 지우면 알림도 함께 지워집니다.
select public.delete_board_post(:'post_id');
select pg_temp.assert_true(jsonb_array_length(public.my_notifications())=0,'글 삭제 시 알림 정리');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.notifications),'알림 연쇄 삭제');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.my_notifications()','42501'),'비로그인 알림 거부');
rollback;
