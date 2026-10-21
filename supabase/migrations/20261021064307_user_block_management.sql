-- 차단 목록은 본인에게만 공개하고 차단 변경은 친구 변경과 같은 순서로 잠급니다.
create function runspot_private.my_blocks()
returns table(user_id uuid,nickname text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return query select b.blocked_id,coalesce(p.nickname,'탈퇴한 사용자')
  from runspot_private.blocks b join public.profiles p on p.id=b.blocked_id
  where b.blocker_id=auth.uid() order by lower(p.nickname),b.blocked_id;
end;
$$;

create function runspot_private.change_my_block(target_id uuid,blocked boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if target_id is null or target_id=viewer or blocked is null then
    raise exception '차단할 사용자를 확인해 주세요.' using errcode='22023';
  end if;
  perform 1 from auth.users where id in (viewer,target_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (viewer,target_id) order by user_id for share;
  perform 1 from public.profiles where id in (viewer,target_id) order by id for update;
  if not runspot_private.is_active(viewer) then
    raise exception '계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if blocked then
    -- 임의 식별자 탐색을 막고 화면에서 접근 가능한 상대만 새로 차단합니다.
    if exists(select 1 from runspot_private.blocks where blocker_id=viewer and blocked_id=target_id) then return; end if;
    if not exists(select 1 from public.profiles p where p.id=target_id and
      (runspot_private.can_read(p.id,p.visibility) or exists(
        select 1 from public.friendships f where f.user_low=least(viewer,target_id)
        and f.user_high=greatest(viewer,target_id)))) then
      raise exception '사용자 정보를 새로고침해 주세요.' using errcode='42501';
    end if;
    insert into runspot_private.blocks(blocker_id,blocked_id) values(viewer,target_id) on conflict do nothing;
    delete from public.friendships where user_low=least(viewer,target_id) and user_high=greatest(viewer,target_id);
  else
    -- 본인이 만든 차단만 해제하며 친구 관계는 복원하지 않습니다.
    delete from runspot_private.blocks where blocker_id=viewer and blocked_id=target_id;
  end if;
end;
$$;

create function public.my_blocks()
returns table(user_id uuid,nickname text)
language sql stable security invoker set search_path = '' as $$ select * from runspot_private.my_blocks(); $$;
create function public.change_my_block(target_id uuid,blocked boolean)
returns void language sql security invoker set search_path = '' as $$ select runspot_private.change_my_block(target_id,blocked); $$;
revoke all on function runspot_private.my_blocks(),runspot_private.change_my_block(uuid,boolean),
  public.my_blocks(),public.change_my_block(uuid,boolean) from public,anon,authenticated;
grant execute on function runspot_private.my_blocks(),runspot_private.change_my_block(uuid,boolean),
  public.my_blocks(),public.change_my_block(uuid,boolean) to authenticated;
notify pgrst,'reload schema';
