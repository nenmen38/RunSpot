-- 러닝 경험치·레벨. 보상은 서버가 기록 저장과 같은 트랜잭션에서 한 번만 계산합니다.
-- 앱은 결과를 조회만 하며 경험치나 레벨을 직접 쓰지 않습니다.
create table runspot_private.run_rewards (
  run_id uuid primary key references public.runs(id) on delete cascade,
  user_id uuid not null,
  xp integer not null check (xp between 0 and 300),
  reason text check (reason in ('too_short','too_fast','late_sync','daily_limit')),
  total_before integer not null check (total_before >= 0),
  level_before integer not null check (level_before between 1 and 99),
  level_after integer not null check (level_after between level_before and 99),
  awarded_at timestamptz not null default now()
);
create index run_rewards_owner on runspot_private.run_rewards(user_id);
alter table runspot_private.run_rewards enable row level security;
revoke all on runspot_private.run_rewards from public, anon, authenticated;

-- Lv.L에서 다음 레벨까지 100 + 50×(L-1) XP가 필요합니다. 최대 Lv.99입니다.
create function runspot_private.level_for_xp(total integer)
returns integer language plpgsql immutable set search_path = '' as $$
declare
  current_level integer := 1;
  floor_xp integer := 0;
begin
  while current_level < 99 and total >= floor_xp + 100 + 50 * (current_level - 1) loop
    floor_xp := floor_xp + 100 + 50 * (current_level - 1);
    current_level := current_level + 1;
  end loop;
  return current_level;
end;
$$;

create function runspot_private.progress_for_xp(total integer)
returns jsonb language sql immutable set search_path = '' as $$
  with l as (select runspot_private.level_for_xp(total) as level)
  select jsonb_build_object(
    'total_xp', total,
    'level', l.level,
    'level_xp', total - (100 * (l.level - 1) + 25 * (l.level - 1) * (l.level - 2)),
    'next_level_xp', case when l.level >= 99 then null else 100 + 50 * (l.level - 1) end
  ) from l;
$$;

create function runspot_private.award_run_reward()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner_total integer;
  day_total integer;
  earned integer;
  why text;
begin
  -- 같은 계정의 동시 저장이 일일 한도와 레벨 계산을 함께 넘지 않도록 직렬화합니다.
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:' || new.user_id::text, 0));
  select coalesce(sum(xp), 0) into owner_total
    from runspot_private.run_rewards where user_id = new.user_id;
  select coalesce(sum(w.xp), 0) into day_total
    from runspot_private.run_rewards w join public.runs r on r.id = w.run_id
    where w.user_id = new.user_id
      and (r.ended_at at time zone 'Asia/Seoul')::date = (new.ended_at at time zone 'Asia/Seoul')::date;

  -- 기기 측정값이므로 짧은 기록·비현실적 속도·오래된 기록은 저장만 하고 보상하지 않습니다.
  if new.distance_m < 300 then
    earned := 0; why := 'too_short';
  elsif new.duration_sec <= 0 or new.distance_m::numeric / new.duration_sec > 6.5 then
    earned := 0; why := 'too_fast';
  elsif new.ended_at < now() - interval '7 days' then
    earned := 0; why := 'late_sync';
  else
    earned := least(300, 10 + new.distance_m / 100);
    if day_total + earned > 500 then
      earned := greatest(0, 500 - day_total); why := 'daily_limit';
    end if;
  end if;

  insert into runspot_private.run_rewards(run_id,user_id,xp,reason,total_before,level_before,level_after)
  values(new.id,new.user_id,earned,why,owner_total,
    runspot_private.level_for_xp(owner_total),runspot_private.level_for_xp(owner_total + earned));
  return null;
end;
$$;
revoke all on function runspot_private.award_run_reward() from public, anon, authenticated;
create trigger runs_award_reward after insert on public.runs
  for each row execute function runspot_private.award_run_reward();

create function runspot_private.my_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode = '42501';
  end if;
  return runspot_private.progress_for_xp(
    (select coalesce(sum(xp), 0)::integer from runspot_private.run_rewards where user_id = owner_id));
end;
$$;

create function runspot_private.my_run_reward(requested_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  reward runspot_private.run_rewards;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode = '42501';
  end if;
  select * into reward from runspot_private.run_rewards
    where run_id = requested_run_id and user_id = owner_id;
  -- 타인 기록과 보상 도입 전 기록은 같은 응답으로 처리해 존재 여부를 드러내지 않습니다.
  if not found then
    return jsonb_build_object('status', 'unavailable', 'run_id', requested_run_id);
  end if;
  return jsonb_build_object(
    'status', 'ready',
    'run_id', reward.run_id,
    'xp', reward.xp,
    'reason', reward.reason,
    'level_before', reward.level_before,
    'level_after', reward.level_after,
    'progress', runspot_private.progress_for_xp(
      (select coalesce(sum(xp), 0)::integer from runspot_private.run_rewards where user_id = owner_id))
  );
end;
$$;

create function public.my_progress()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_progress();
$$;
create function public.my_run_reward(requested_run_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_run_reward(requested_run_id);
$$;

revoke all on function runspot_private.level_for_xp(integer), runspot_private.progress_for_xp(integer),
  runspot_private.my_progress(), runspot_private.my_run_reward(uuid),
  public.my_progress(), public.my_run_reward(uuid)
  from public, anon, authenticated;
grant execute on function runspot_private.my_progress(), runspot_private.my_run_reward(uuid),
  public.my_progress(), public.my_run_reward(uuid)
  to authenticated;
notify pgrst, 'reload schema';
