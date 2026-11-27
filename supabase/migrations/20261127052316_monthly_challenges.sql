-- 개인 월간 챌린지: 매달 '50km 달리기', '주말에 4번 달리기', '10일 달리기' 세 가지 도전을 줍니다.
-- 달성하면 완료 기록이 남고, 12월에 세 가지를 모두 마치면 '산타 러닝캡'을 선물합니다(상점에서는 살 수 없음).

create or replace function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('share_minimal','share_night') then 'share_card'
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
    when item in ('char_cap_blue','char_cap_black','char_visor_white','char_headband_red','char_headband_gold','char_cap_santa') then 'char_head'
    when item in ('char_glasses_black','char_glasses_mirror') then 'char_eyes'
    when item in ('char_singlet_orange','char_tee_mint','char_tee_navy','char_singlet_gold') then 'char_top'
    when item in ('char_shorts_black','char_shorts_blue') then 'char_bottom'
    when item in ('char_sleeves_black','char_sleeves_neon') then 'char_sleeves'
    when item in ('char_shoes_red','char_shoes_neon','char_shoes_carbon','char_shoes_rainbow') then 'char_shoes'
  end;
$$;

create table runspot_private.challenge_completions (
  user_id uuid not null references auth.users(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  code text not null check (code in ('distance_50k', 'weekend_4', 'days_10')),
  completed_at timestamptz not null default now(),
  primary key (user_id, month, code)
);
alter table runspot_private.challenge_completions enable row level security;
revoke all on runspot_private.challenge_completions from public, anon, authenticated;

-- 한 달의 챌린지 진행도를 계산하고, 달성한 것은 완료로 기록합니다(이번 달까지만).
create function runspot_private.my_challenges(requested_month date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  this_month date := date_trunc('month', now() at time zone 'Asia/Seoul')::date;
  first_day date := date_trunc('month', coalesce(requested_month, this_month))::date;
  next_month date := (first_day + interval '1 month')::date;
  meters integer;
  weekend_runs integer;
  days integer;
  items jsonb;
  all_done boolean;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode = '42501';
  end if;
  if first_day > this_month then
    raise exception '아직 시작하지 않은 달이에요.' using errcode = '22023';
  end if;
  select coalesce(sum(r.distance_m), 0),
    count(*) filter (where extract(isodow from r.ended_at at time zone 'Asia/Seoul') in (6, 7)),
    count(distinct (r.ended_at at time zone 'Asia/Seoul')::date)
  into meters, weekend_runs, days
  from public.runs r
  where r.user_id = viewer and not r.review_pending and r.integrity_status <> 'rejected' and not r.hidden
    and (r.ended_at at time zone 'Asia/Seoul')::date >= first_day
    and (r.ended_at at time zone 'Asia/Seoul')::date < next_month;

  insert into runspot_private.challenge_completions(user_id, month, code)
  select viewer, first_day, c.code
  from (values ('distance_50k', meters >= 50000), ('weekend_4', weekend_runs >= 4), ('days_10', days >= 10)) c(code, done)
  where c.done
  on conflict do nothing;

  all_done := (select count(*) = 3 from runspot_private.challenge_completions
    where user_id = viewer and month = first_day);
  -- 12월 챌린지를 모두 마치면 산타 러닝캡을 선물합니다.
  if all_done and extract(month from first_day) = 12 then
    insert into runspot_private.owned_cosmetics(user_id, item, coins)
    values (viewer, 'char_cap_santa', 0) on conflict do nothing;
  end if;

  items := jsonb_build_array(
    jsonb_build_object('code', 'distance_50k', 'progress', least(meters, 50000), 'goal', 50000),
    jsonb_build_object('code', 'weekend_4', 'progress', least(weekend_runs, 4), 'goal', 4),
    jsonb_build_object('code', 'days_10', 'progress', least(days, 10), 'goal', 10)
  );
  return jsonb_build_object(
    'month', first_day,
    'challenges', items,
    'all_done', all_done,
    'reward_item', case when extract(month from first_day) = 12 then 'char_cap_santa' end,
    'completed_months', (select count(*) from (
      select month from runspot_private.challenge_completions where user_id = viewer
      group by month having count(*) = 3) done)
  );
end;
$$;
create function public.my_challenges(requested_month date default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.my_challenges(requested_month); $$;
revoke all on function runspot_private.my_challenges(date), public.my_challenges(date) from public, anon, authenticated;
grant execute on function runspot_private.my_challenges(date), public.my_challenges(date) to authenticated;
notify pgrst, 'reload schema';
