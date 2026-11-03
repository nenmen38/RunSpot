-- 볼 수 있는 게시글·댓글의 작성자만 조회하거나 차단합니다. 비공개 프로필도 게시판에서 차단할 수 있습니다.
create function runspot_private.board_user_interaction(target_post uuid,target_comment uuid,operation text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid(); target_user uuid; target_name text;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  if operation is null or operation not in ('view','block') then
    raise exception '요청을 확인해 주세요.' using errcode='22023';
  end if;
  perform runspot_private.require_visible_board_post(target_post,viewer);
  if target_comment is null then
    select author_id into target_user from runspot_private.board_posts where id=target_post;
  else
    select author_id into target_user from runspot_private.board_comments
      where id=target_comment and post_id=target_post;
  end if;
  if target_user is null or not runspot_private.board_author_visible(target_user,viewer) then
    raise exception '사용자를 확인할 수 없습니다.' using errcode='42501';
  end if;
  if operation='block' then
    if target_user=viewer then raise exception '본인은 차단할 수 없습니다.' using errcode='22023'; end if;
    -- 기존 차단 API와 같은 잠금 순서를 유지합니다. 차단 트리거가 함께 달리기도 정리합니다.
    perform 1 from auth.users where id in (viewer,target_user) order by id for share;
    perform 1 from runspot_private.account_controls where user_id in (viewer,target_user) order by user_id for share;
    perform 1 from public.profiles where id in (viewer,target_user) order by id for update;
    perform runspot_private.require_visible_board_post(target_post,viewer);
    if not runspot_private.is_active(viewer) or not runspot_private.board_author_visible(target_user,viewer) then
      raise exception '사용자 정보를 새로고침해 주세요.' using errcode='42501';
    end if;
    insert into runspot_private.blocks(blocker_id,blocked_id) values(viewer,target_user) on conflict do nothing;
    delete from public.friendships where user_low=least(viewer,target_user) and user_high=greatest(viewer,target_user);
  end if;
  select coalesce(nickname,'사용자') into target_name from public.profiles where id=target_user;
  return jsonb_build_object('user_id',target_user,'nickname',target_name);
end;
$$;
create function public.board_user_interaction(target_post uuid,target_comment uuid default null,operation text default 'view')
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.board_user_interaction(target_post,target_comment,operation);
$$;
revoke all on function runspot_private.board_user_interaction(uuid,uuid,text),public.board_user_interaction(uuid,uuid,text) from public,anon,authenticated;
grant execute on function runspot_private.board_user_interaction(uuid,uuid,text),public.board_user_interaction(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
