-- 친구·크루원 화면에서 다른 러너가 입은 캐릭터 아이템을 보여 줍니다.
-- 사진과 같은 규칙으로, 탈퇴·정지했거나 서로 차단한 사람은 빠집니다. 캐릭터 칸(char_*)만 돌려줍니다.
-- 결과: {"사용자 ID": {"char_head": "char_cap_blue", ...}} (아무것도 안 입었으면 빈 객체)
create function runspot_private.runner_characters(user_ids uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if cardinality(coalesce(user_ids, '{}')) > 100 then
    raise exception '캐릭터는 한 번에 100명까지 조회할 수 있어요.' using errcode = '22023';
  end if;
  return (
    select coalesce(jsonb_object_agg(u.id, coalesce((
      select jsonb_object_agg(e.slot, e.item)
      from runspot_private.equipped_cosmetics e
      where e.user_id = u.id and e.slot like 'char\_%'
    ), '{}'::jsonb)), '{}'::jsonb)
    from (select distinct id from unnest(coalesce(user_ids, '{}')) as ids(id)) u
    where u.id = viewer or runspot_private.board_author_visible(u.id, viewer)
  );
end;
$$;
create function public.runner_characters(user_ids uuid[] default '{}')
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.runner_characters(user_ids); $$;
revoke all on function runspot_private.runner_characters(uuid[]), public.runner_characters(uuid[])
  from public, anon, authenticated;
grant execute on function runspot_private.runner_characters(uuid[]), public.runner_characters(uuid[])
  to authenticated;
notify pgrst, 'reload schema';
