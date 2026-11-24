-- 지급 장부는 보존하고, 새 보상은 사용자가 직접 수령합니다.
drop trigger run_rewards_weekly_coins on runspot_private.run_rewards;
drop function runspot_private.award_weekly_coins();

create function runspot_private.claim_weekly_coin_quest(requested_quest text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  current_week date := date_trunc('week', now() at time zone 'Asia/Seoul')::date;
begin
  if requested_quest is null
    or requested_quest not in ('two_days', 'single_3k', 'total_8k') then
    raise exception using errcode = '22023', message = '올바른 퀘스트를 선택해 주세요.';
  end if;

  -- 기록 검토와 보상 수령을 직렬화하고, 같은 퀘스트의 중복 적립을 막습니다.
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:' || viewer::text, 0));

  if not exists (
    select 1 from runspot_private.weekly_coin_rewards w
    where w.user_id = viewer and w.week_start = current_week and w.quest = requested_quest
  ) then
    insert into runspot_private.weekly_coin_rewards(user_id, week_start, quest, coins)
    select viewer, current_week, q.quest, q.coins
    from runspot_private.weekly_coin_quests(viewer, current_week) q
    where q.quest = requested_quest and q.progress >= q.goal
    on conflict do nothing;

    if not found then
      raise exception using errcode = 'P0001', message = '이번 주 퀘스트를 아직 완료하지 않았습니다.';
    end if;
  end if;

  return runspot_private.wallet_json(viewer);
end;
$$;

create function public.claim_weekly_coin_quest(requested_quest text)
returns jsonb
language sql security invoker set search_path = '' as $$
  select runspot_private.claim_weekly_coin_quest(requested_quest);
$$;

revoke all on function runspot_private.claim_weekly_coin_quest(text),
  public.claim_weekly_coin_quest(text) from public, anon, authenticated, service_role;
grant execute on function runspot_private.claim_weekly_coin_quest(text),
  public.claim_weekly_coin_quest(text) to authenticated;

notify pgrst, 'reload schema';
