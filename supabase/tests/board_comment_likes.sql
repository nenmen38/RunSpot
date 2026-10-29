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
  update runspot_private.board_comments set created_at=created_at-interval '1 minute';
$$;
grant execute on function pg_temp.age_board() to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000171','clike171@example.com',now()),
 ('00000000-0000-0000-0000-000000000172','clike172@example.com',now()),
 ('00000000-0000-0000-0000-000000000173','clike173@example.com',null);
update public.profiles set nickname='댓글좋아요'||right(id::text,3),visibility='public'
where id::text like '%00000000017_' and id<>'00000000-0000-0000-0000-000000000173';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select public.create_board_post(gen_random_uuid(),'national','한강 코스','같이 뛰어요','course') as post_id \gset
select public.create_board_comment(gen_random_uuid(),:'post_id','첫 댓글') as comment_id \gset
select pg_temp.age_board();
select public.create_board_comment(gen_random_uuid(),:'post_id','답글',:'comment_id') as reply_id \gset
select pg_temp.assert_true((select (c->>'like_count')::int=0 and not (c->>'liked')::boolean
  from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c where c->>'id'=:'comment_id'),'좋아요 없음 표시');

-- 댓글과 답글에 좋아요를 누르고 취소할 수 있으며 반복해도 결과가 같습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000172',true);
select pg_temp.assert_true((public.set_board_comment_like(:'comment_id',true)->>'like_count')::int=1,'댓글 좋아요');
select pg_temp.assert_true((public.set_board_comment_like(:'comment_id',true)->>'like_count')::int=1,'댓글 좋아요 멱등성');
select pg_temp.assert_true((public.set_board_comment_like(:'reply_id',true)->>'like_count')::int=1,'답글 좋아요');
select pg_temp.assert_true((select (c->>'like_count')::int=1 and (c->>'liked')::boolean
  from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c where c->>'id'=:'reply_id'),'답글 좋아요 표시');
select pg_temp.assert_true((public.set_board_comment_like(:'reply_id',false)->>'like_count')::int=0,'답글 좋아요 취소');
select pg_temp.assert_true(pg_temp.fails('select public.set_board_comment_like(''00000000-0000-0000-0000-00000000dead'',true)','P0001'),'없는 댓글 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.set_board_comment_like(%L,null)',:'comment_id'),'22023'),'좋아요 상태 필요');

-- 미인증 사용자는 누를 수 없고, 차단한 상대의 좋아요는 집계에서 빠집니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000173',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.set_board_comment_like(%L,true)',:'comment_id'),'42501'),'미인증 좋아요 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select public.change_my_block('00000000-0000-0000-0000-000000000172',true);
select pg_temp.assert_true((select (c->>'like_count')::int=0
  from jsonb_array_elements(public.board_comments(:'post_id')->'comments') c where c->>'id'=:'comment_id'),'차단 상대 좋아요 제외');
select public.change_my_block('00000000-0000-0000-0000-000000000172',false);
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_comment_likes','42501'),'좋아요 원본 접근 거부');

-- 댓글을 지우면 좋아요도 함께 지워집니다.
select public.delete_board_comment(:'comment_id');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.board_comment_likes),'댓글 삭제 시 좋아요 정리');
rollback;
