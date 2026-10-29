-- 댓글·답글 좋아요입니다. 원본은 비노출 스키마에 두고 RPC로만 접근합니다.
create table runspot_private.board_comment_likes (
  comment_id uuid not null references runspot_private.board_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(comment_id,user_id)
);
create index board_comment_likes_user on runspot_private.board_comment_likes(user_id);
alter table runspot_private.board_comment_likes enable row level security;
revoke all on runspot_private.board_comment_likes from public,anon,authenticated;

-- 볼 수 있는 댓글에만 좋아요를 누를 수 있습니다. 답글은 원댓글도 보여야 합니다.
create function runspot_private.set_board_comment_like(comment_id uuid,liked boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  item runspot_private.board_comments;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 좋아요를 누를 수 있습니다.' using errcode='42501';
  end if;
  if liked is null then raise exception '좋아요 상태를 확인해 주세요.' using errcode='22023'; end if;
  select * into item from runspot_private.board_comments c where c.id=set_board_comment_like.comment_id;
  if not found or not runspot_private.board_post_visible(item.post_id,viewer)
    or not runspot_private.board_author_visible(item.author_id,viewer)
    or (item.parent_id is not null and not exists(select 1 from runspot_private.board_comments pc
      where pc.id=item.parent_id and runspot_private.board_author_visible(pc.author_id,viewer))) then
    raise exception '삭제되었거나 볼 수 없는 댓글입니다.' using errcode='P0001';
  end if;
  -- 같은 요청을 반복해도 결과가 같도록 추가·삭제를 멱등으로 처리합니다.
  if liked then
    insert into runspot_private.board_comment_likes(comment_id,user_id) values(item.id,viewer) on conflict do nothing;
  else
    delete from runspot_private.board_comment_likes l where l.comment_id=item.id and l.user_id=viewer;
  end if;
  return jsonb_build_object('liked',liked,'like_count',(select count(*) from runspot_private.board_comment_likes l
    where l.comment_id=item.id and runspot_private.board_author_visible(l.user_id,viewer)));
end;
$$;

-- 댓글 목록에 좋아요 수와 내 좋아요 여부를 더합니다.
create or replace function runspot_private.board_comments(post_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  perform runspot_private.require_visible_board_post(post_id,viewer);
  return jsonb_build_object('can_write',runspot_private.can_interact(),
    'can_moderate',runspot_private.staff_role() is not null,
    'comments',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'parent_id',c.parent_id,'body',c.body,
      'nickname',coalesce(pr.nickname,'닉네임 없음'),'is_mine',c.author_id=viewer,'created_at',c.created_at,
      'like_count',(select count(*) from runspot_private.board_comment_likes l where l.comment_id=c.id
        and runspot_private.board_author_visible(l.user_id,viewer)),
      'liked',exists(select 1 from runspot_private.board_comment_likes l where l.comment_id=c.id and l.user_id=viewer))
      order by c.created_at,c.id),'[]'::jsonb)
    from (select * from runspot_private.board_comments c where c.post_id=board_comments.post_id
      and runspot_private.board_author_visible(c.author_id,viewer)
      and (c.parent_id is null or exists(select 1 from runspot_private.board_comments pc
        where pc.id=c.parent_id and runspot_private.board_author_visible(pc.author_id,viewer)))
      order by c.created_at,c.id limit 300) c
    left join public.profiles pr on pr.id=c.author_id));
end;
$$;

create function public.set_board_comment_like(comment_id uuid,liked boolean)
returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.set_board_comment_like(comment_id,liked); $$;
revoke all on function runspot_private.set_board_comment_like(uuid,boolean),public.set_board_comment_like(uuid,boolean)
  from public,anon,authenticated;
grant execute on function runspot_private.set_board_comment_like(uuid,boolean),public.set_board_comment_like(uuid,boolean)
  to authenticated;
notify pgrst,'reload schema';
