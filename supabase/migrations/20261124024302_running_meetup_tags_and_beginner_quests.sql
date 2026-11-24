-- 모임 주최자가 선택한 진행 방식과 참가 대상 안내를 저장합니다.
alter table runspot_private.meetups
  add column beginner_friendly boolean not null default false,
  add column walk_run boolean not null default false,
  add column women_focused boolean not null default false,
  add column waits_for_group boolean not null default false;

create function runspot_private.meetup_list_with_tags(region_filter text default '',pace_filter integer default null,only_mine boolean default false,page_offset integer default 0, required_tags text[] default array[]::text[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 if required_tags is null or not required_tags <@ array['beginner','walk_run','women']::text[] then
   raise exception '모임 필터를 확인해 주세요.' using errcode='22023';
 end if;
 if page_offset<0 or page_offset>10000 or length(region_filter)>40 then raise exception '검색 조건을 확인해 주세요.' using errcode='22023'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at,x.id),'[]') from (
 select m.id,m.title,m.region,m.place,m.starts_at,m.distance_km,m.pace_seconds,m.capacity,m.cancelled,m.group_id,
   m.beginner_friendly,m.walk_run,m.women_focused,m.waits_for_group,
   p.nickname as host_name,m.host_id=auth.uid() as is_host,
   exists(select 1 from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=auth.uid()) as joined,
   (select count(*) from runspot_private.meetup_members u where u.meetup_id=m.id) as member_count
 from runspot_private.meetups m join public.profiles p on p.id=m.host_id
 where runspot_private.meetup_visible(m.host_id) and m.starts_at>now()-interval '6 hours'
   and (not m.cancelled or only_mine)
   and (coalesce(region_filter,'')='' or position(lower(region_filter) in lower(m.region))>0)
   and (pace_filter is null or abs(m.pace_seconds-pace_filter)<=30)
   and ('beginner' <> all(required_tags) or m.beginner_friendly)
   and ('walk_run' <> all(required_tags) or m.walk_run)
   and ('women' <> all(required_tags) or m.women_focused)
   and (not only_mine or exists(select 1 from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=auth.uid()))
 order by m.starts_at,m.id limit 30 offset page_offset
 )x);
end;
$$;

create function runspot_private.meetup_create_with_tags(
 request_id uuid,title text,region text,place text,starts_at timestamptz,
 distance_km integer,pace_seconds integer,capacity integer,
 beginner_friendly boolean,walk_run boolean,women_focused boolean,waits_for_group boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare meetup uuid;
begin
 meetup := runspot_private.meetup_create(request_id,title,region,place,starts_at,
   distance_km,pace_seconds,capacity);
 update runspot_private.meetups m
 set beginner_friendly=coalesce(meetup_create_with_tags.beginner_friendly,false),
   walk_run=coalesce(meetup_create_with_tags.walk_run,false),
   women_focused=coalesce(meetup_create_with_tags.women_focused,false),
   waits_for_group=coalesce(meetup_create_with_tags.waits_for_group,false)
 where m.id=meetup and m.host_id=auth.uid();
 return meetup;
end;
$$;

create function public.meetup_list_with_tags(
 region_filter text, pace_filter integer, only_mine boolean, page_offset integer, required_tags text[]
) returns jsonb language sql stable security invoker set search_path='' as $$
 select runspot_private.meetup_list_with_tags(region_filter,pace_filter,only_mine,page_offset,required_tags);
$$;

create function public.meetup_create_with_tags(
 request_id uuid,title text,region text,place text,starts_at timestamptz,
 distance_km integer,pace_seconds integer,capacity integer,
 beginner_friendly boolean,walk_run boolean,women_focused boolean,waits_for_group boolean
) returns uuid language sql security invoker set search_path='' as $$
 select runspot_private.meetup_create_with_tags(request_id,title,region,place,starts_at,
   distance_km,pace_seconds,capacity,beginner_friendly,walk_run,women_focused,waits_for_group);
$$;

revoke all on function
  public.meetup_list_with_tags(text,integer,boolean,integer,text[]),
  runspot_private.meetup_list_with_tags(text,integer,boolean,integer,text[]),
  public.meetup_create_with_tags(uuid,text,text,text,timestamptz,integer,integer,integer,boolean,boolean,boolean,boolean),
  runspot_private.meetup_create_with_tags(uuid,text,text,text,timestamptz,integer,integer,integer,boolean,boolean,boolean,boolean)
from public,anon,authenticated,service_role;
grant execute on function
  public.meetup_list_with_tags(text,integer,boolean,integer,text[]),
  runspot_private.meetup_list_with_tags(text,integer,boolean,integer,text[]),
  public.meetup_create_with_tags(uuid,text,text,text,timestamptz,integer,integer,integer,boolean,boolean,boolean,boolean),
  runspot_private.meetup_create_with_tags(uuid,text,text,text,timestamptz,integer,integer,integer,boolean,boolean,boolean,boolean)
to authenticated;

-- 같은 주간 지급 장부를 사용하되, 새 목표의 지급 코인만 허용합니다.
alter table runspot_private.weekly_coin_rewards
  drop constraint weekly_coin_rewards_check,
  add check ((quest='two_days' and coins=20)
    or (quest in ('single_3k','total_8k','active_20m','short_runs','group_run') and coins=5));

create or replace function runspot_private.weekly_coin_quests(target uuid, week_start date)
returns table(display_order integer, quest text, progress integer, goal integer, coins integer)
language sql stable set search_path = '' as $$
  with eligible as (
    select r.id, r.distance_m, r.duration_sec, (r.started_at at time zone 'Asia/Seoul')::date as run_day
    from public.runs r join runspot_private.run_rewards w on w.run_id=r.id
    where r.user_id=target and r.distance_m>=300 and w.xp>0
      and not r.review_pending and r.integrity_status<>'rejected'
      and (r.motion_evidence is not null or r.integrity_status='verified')
      and r.started_at>=greatest(week_start::timestamp at time zone 'Asia/Seoul',
        (select quests_start_at from runspot_private.coin_economy_settings))
      and r.started_at<(week_start+7)::timestamp at time zone 'Asia/Seoul'
      and r.ended_at<=now()
  ), totals as (
    select count(distinct run_day) filter(where distance_m>=1000)::integer as days,
      coalesce(max(distance_m),0)::integer as longest,
      least(8000,coalesce(sum(distance_m) filter(where distance_m>=1000),0))::integer as distance,
      least(1200,coalesce(sum(duration_sec),0))::integer as active_seconds,
      least(2,count(*))::integer as short_runs,
      (exists(select 1 from eligible e join runspot_private.running_group_members gm
        on gm.run_id=e.id and gm.user_id=target where gm.status='finished'))::integer as group_runs
    from eligible
  )
  select q.* from totals t cross join lateral (values
    (1,'two_days',t.days,2,20),
    (2,'single_3k',t.longest,3000,5),
    (3,'total_8k',t.distance,8000,5),
    (4,'active_20m',t.active_seconds,1200,5),
    (5,'short_runs',t.short_runs,2,5),
    (6,'group_run',t.group_runs,1,5)
  ) q(display_order,quest,progress,goal,coins);
$$;

create or replace function runspot_private.claim_weekly_coin_quest(requested_quest text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  current_week date := date_trunc('week', now() at time zone 'Asia/Seoul')::date;
begin
  if requested_quest is null
    or requested_quest not in ('two_days', 'single_3k', 'total_8k', 'active_20m', 'short_runs', 'group_run') then
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

-- 공유에 선택할 수 있는 성과만 반환하며, 기록과 참여자 정보는 공개하지 않습니다.
create function runspot_private.my_run_share_milestones(requested_run uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  viewer uuid := auth.uid();
  selected public.runs;
  month_start timestamp;
begin
  if viewer is null then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  select r.* into selected from public.runs r
  where r.id=requested_run and r.user_id=viewer
    and not r.review_pending and r.integrity_status<>'rejected';
  if not found then
    return jsonb_build_object('first_5k',false,'monthly_runs',0,'together',false);
  end if;
  month_start := date_trunc('month', selected.started_at at time zone 'Asia/Seoul');
  return jsonb_build_object(
    'first_5k',selected.distance_m>=5000 and not exists(
      select 1 from public.runs r where r.user_id=viewer and r.distance_m>=5000
        and not r.review_pending and r.integrity_status<>'rejected'
        and (r.started_at,r.id)<(selected.started_at,selected.id)
    ),
    'monthly_runs',(
      select count(*) from public.runs r where r.user_id=viewer and r.distance_m>=300
        and not r.hidden and not r.review_pending and r.integrity_status<>'rejected'
        and r.started_at>=month_start at time zone 'Asia/Seoul'
        and (r.started_at,r.id)<=(selected.started_at,selected.id)
    ),
    'together',exists(
      select 1 from runspot_private.running_group_members gm
      where gm.run_id=selected.id and gm.user_id=viewer and gm.status='finished'
      and exists(select 1 from runspot_private.running_group_members peer
        where peer.group_id=gm.group_id and peer.user_id<>viewer and peer.status='finished')
    )
  );
end;
$$;

create function public.my_run_share_milestones(requested_run uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select runspot_private.my_run_share_milestones(requested_run);
$$;
revoke all on function public.my_run_share_milestones(uuid),
  runspot_private.my_run_share_milestones(uuid) from public,anon,authenticated,service_role;
grant execute on function public.my_run_share_milestones(uuid),
  runspot_private.my_run_share_milestones(uuid) to authenticated;

notify pgrst, 'reload schema';
