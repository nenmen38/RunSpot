-- 달성형 칭호와 코인 꾸미기 아이템, 크루 정원 확장권입니다.
-- 칭호는 달려서만 얻고(돈으로 살 수 없음), 상점에서는 칭호를 보여주는 모양·경로 색·오라 효과·말풍선만 팝니다.

-- 1) 꾸미기 아이템 ------------------------------------------------------------
-- 아이템마다 착용 칸(slot)이 있고, 칸마다 하나만 착용합니다.
create function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
  end;
$$;

-- 판매 가격(코인)입니다. 1,100원 = 100코인 기준입니다.
create function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path='' as $$
  select case item
    when 'route_neon' then 400 when 'route_gold' then 600 when 'route_rainbow' then 800
    when 'title_gold' then 300 when 'title_neon' then 400 when 'title_gradient' then 500
    when 'title_crown' then 300 when 'title_fire' then 300
    when 'aura_sparkle' then 1600 when 'aura_flame' then 1600 when 'aura_wave' then 1600
    when 'bubble_mint' then 200 when 'bubble_sunset' then 200 when 'bubble_night' then 200 when 'bubble_pink' then 200
  end;
$$;

create table runspot_private.owned_cosmetics (
  user_id uuid not null references auth.users(id) on delete cascade,
  item text not null check (runspot_private.cosmetic_slot(item) is not null),
  coins integer not null check (coins >= 0),
  purchased_at timestamptz not null default now(),
  primary key(user_id,item)
);
create table runspot_private.equipped_cosmetics (
  user_id uuid not null references auth.users(id) on delete cascade,
  slot text not null check (slot in ('route','title_style','aura_effect','chat_bubble')),
  item text not null,
  updated_at timestamptz not null default now(),
  primary key(user_id,slot),
  check (runspot_private.cosmetic_slot(item)=slot)
);

-- 2) 크루 정원 확장권 ---------------------------------------------------------
-- 크루장이 크루 하나에 한 번 살 수 있고, 정원이 30명에서 50명으로 늘어납니다.
create table runspot_private.crew_expansions (
  crew_id uuid primary key references runspot_private.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  coins integer not null check (coins >= 0),
  purchased_at timestamptz not null default now()
);
create index crew_expansions_user on runspot_private.crew_expansions(user_id);
create function runspot_private.crew_expansion_price()
returns integer language sql immutable set search_path='' as $$ select 1000; $$;

-- 크루마다 정원이 다르므로 크루를 받는 정원 함수를 따로 둡니다.
create function runspot_private.crew_size_limit(target uuid)
returns integer language sql stable security definer set search_path='' as $$
  select runspot_private.crew_size_limit()
    + case when exists(select 1 from runspot_private.crew_expansions where crew_id=target) then 20 else 0 end;
$$;

-- 3) 달성형 칭호 --------------------------------------------------------------
create table runspot_private.title_choices (
  user_id uuid primary key references auth.users(id) on delete cascade,
  title text not null check (title in ('ten_k','half','dawn','steady','crew_leader','together')),
  updated_at timestamptz not null default now()
);
alter table runspot_private.owned_cosmetics enable row level security;
alter table runspot_private.equipped_cosmetics enable row level security;
alter table runspot_private.crew_expansions enable row level security;
alter table runspot_private.title_choices enable row level security;
revoke all on runspot_private.owned_cosmetics,runspot_private.equipped_cosmetics,
  runspot_private.crew_expansions,runspot_private.title_choices from public,anon,authenticated;

-- 칭호마다 지금까지의 진행과 목표입니다. 진행이 목표 이상이면 얻은 칭호입니다.
-- 반려된 기록은 세지 않습니다.
create function runspot_private.title_progress(target uuid)
returns table(title text,progress integer,goal integer)
language sql stable security definer set search_path='' as $$
  select 'ten_k',coalesce((select max(distance_m) from public.runs
      where user_id=target and integrity_status<>'rejected'),0),10000
  union all
  select 'half',coalesce((select max(distance_m) from public.runs
      where user_id=target and integrity_status<>'rejected'),0),21097
  union all
  select 'dawn',(select count(*)::integer from public.runs
      where user_id=target and integrity_status<>'rejected'
        and extract(hour from started_at at time zone 'Asia/Seoul') < 6),10
  union all
  -- 지난주부터 거꾸로, 주간 목표를 연속으로 달성한 주 수입니다(최대 4).
  select 'steady',coalesce((
    with goal as (select kilometers*1000 as meters from runspot_private.weekly_goals
        where user_id=target and kilometers is not null),
      weeks as (
        select w,(select coalesce(sum(r.distance_m),0) from public.runs r
            where r.user_id=target and r.integrity_status<>'rejected'
              and r.started_at >= (date_trunc('week',now() at time zone 'Asia/Seoul') - (w*interval '1 week')) at time zone 'Asia/Seoul'
              and r.started_at < (date_trunc('week',now() at time zone 'Asia/Seoul') - ((w-1)*interval '1 week')) at time zone 'Asia/Seoul') as meters
        from generate_series(1,4) w)
    select coalesce(min(w)-1,4)::integer from weeks,goal where weeks.meters < goal.meters
  ),0)*case when exists(select 1 from runspot_private.weekly_goals where user_id=target and kilometers is not null) then 1 else 0 end,4
  union all
  select 'crew_leader',coalesce((select max((select count(*) from runspot_private.crew_members m where m.crew_id=c.id))::integer
      from runspot_private.crews c where c.owner_id=target),0),10
  union all
  select 'together',(select count(*)::integer from runspot_private.running_group_members
      where user_id=target and status='finished'),10;
$$;
revoke all on function runspot_private.title_progress(uuid) from public,anon,authenticated;

create function runspot_private.title_earned(target uuid,requested text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from runspot_private.title_progress(target) t
    where t.title=requested and t.progress>=t.goal);
$$;
revoke all on function runspot_private.title_earned(uuid,text) from public,anon,authenticated;

create function runspot_private.my_titles()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return jsonb_build_object(
    'selected',(select c.title from runspot_private.title_choices c
      where c.user_id=viewer and runspot_private.title_earned(viewer,c.title)),
    'titles',(select jsonb_agg(jsonb_build_object('code',t.title,'progress',least(t.progress,t.goal),
        'goal',t.goal,'earned',t.progress>=t.goal)) from runspot_private.title_progress(viewer) t));
end;
$$;

-- 얻은 칭호만 고를 수 있습니다. null이면 칭호를 떼어 냅니다.
create function runspot_private.set_title(requested text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if requested is null then
    delete from runspot_private.title_choices where user_id=viewer;
  elsif not runspot_private.title_earned(viewer,requested) then
    raise exception '아직 얻지 못한 칭호예요.' using errcode='P0001';
  else
    insert into runspot_private.title_choices(user_id,title) values(viewer,requested)
    on conflict(user_id) do update set title=excluded.title,updated_at=now();
  end if;
  return runspot_private.my_titles();
end;
$$;

-- 4) 잔액·지갑 ---------------------------------------------------------------
create or replace function runspot_private.coin_balance(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select runspot_private.level_coins(runspot_private.user_level(target))
    + coalesce((select sum(coins) from runspot_private.coin_purchases
        where user_id=target and refunded_at is null),0)::integer
    + coalesce((select sum(coins) from runspot_private.coin_grants where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_frames where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.crew_tickets where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_cosmetics where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.crew_expansions where user_id=target),0)::integer;
$$;

create or replace function runspot_private.wallet_json(target uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with l as (select runspot_private.user_level(target) as level)
  select jsonb_build_object(
    'coins',runspot_private.coin_balance(target),
    'level',l.level,
    'level_coins',runspot_private.level_coins(l.level),
    'next_reward_level',case when l.level < 99 then l.level+1 end,
    'next_reward_coins',case when l.level < 99
      then runspot_private.level_coins(l.level+1)-runspot_private.level_coins(l.level) end,
    'prices',jsonb_build_object('basic',runspot_private.frame_price('basic'),
      'aura',runspot_private.frame_price('aura'),'crew_ticket',runspot_private.crew_ticket_price(),
      'crew_expansion',runspot_private.crew_expansion_price()),
    'owned',(select coalesce(jsonb_agg(frame order by frame),'[]'::jsonb)
      from runspot_private.owned_frames where user_id=target),
    'equipped',(select frame from runspot_private.frame_settings where user_id=target),
    'color',coalesce((select color from runspot_private.frame_settings where user_id=target),'#3182F6'),
    'crew_tickets',(select count(*) from runspot_private.crew_tickets where user_id=target and used_at is null),
    'in_crew',exists(select 1 from runspot_private.crew_members where user_id=target),
    'cosmetics',jsonb_build_object(
      'owned',(select coalesce(jsonb_agg(item order by item),'[]'::jsonb)
        from runspot_private.owned_cosmetics where user_id=target),
      'equipped',(select coalesce(jsonb_object_agg(slot,item),'{}'::jsonb)
        from runspot_private.equipped_cosmetics where user_id=target)))
  from l;
$$;

create function runspot_private.buy_cosmetic(requested_item text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); price integer;
begin
  price := runspot_private.cosmetic_price(requested_item);
  if price is null then raise exception '아이템을 확인해 주세요.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('coins:'||viewer::text,0));
  if exists(select 1 from runspot_private.owned_cosmetics where user_id=viewer and item=requested_item) then
    return runspot_private.wallet_json(viewer);
  end if;
  if runspot_private.coin_balance(viewer) < price then
    raise exception '코인이 부족합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.owned_cosmetics(user_id,item,coins) values(viewer,requested_item,price);
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 가진 아이템만 착용합니다. requested_item이 null이면 그 칸을 비웁니다.
create function runspot_private.equip_cosmetic(requested_slot text,requested_item text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if requested_slot is null or requested_slot not in ('route','title_style','aura_effect','chat_bubble') then
    raise exception '착용할 곳을 확인해 주세요.' using errcode='22023';
  end if;
  if requested_item is null then
    delete from runspot_private.equipped_cosmetics where user_id=viewer and slot=requested_slot;
    return runspot_private.wallet_json(viewer);
  end if;
  if runspot_private.cosmetic_slot(requested_item) is distinct from requested_slot then
    raise exception '이 칸에 착용할 수 없는 아이템이에요.' using errcode='22023';
  end if;
  if not exists(select 1 from runspot_private.owned_cosmetics where user_id=viewer and item=requested_item) then
    raise exception '가진 아이템만 착용할 수 있습니다.' using errcode='P0001';
  end if;
  insert into runspot_private.equipped_cosmetics(user_id,slot,item) values(viewer,requested_slot,requested_item)
  on conflict(user_id,slot) do update set item=excluded.item,updated_at=now();
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 크루장만 자기 크루를 한 번 확장할 수 있습니다.
create function runspot_private.expand_crew(requested_crew uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); price integer := runspot_private.crew_expansion_price();
begin
  perform pg_advisory_xact_lock(hashtextextended('coins:'||viewer::text,0));
  if not exists(select 1 from runspot_private.crews where id=requested_crew and owner_id=viewer) then
    raise exception '크루장만 정원을 늘릴 수 있습니다.' using errcode='42501';
  end if;
  if exists(select 1 from runspot_private.crew_expansions where crew_id=requested_crew) then
    raise exception '이미 정원을 늘린 크루예요.' using errcode='P0001';
  end if;
  if runspot_private.coin_balance(viewer) < price then
    raise exception '코인이 부족합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.crew_expansions(crew_id,user_id,coins) values(requested_crew,viewer,price);
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 5) 다른 사람에게 보이는 칭호·꾸미기 -----------------------------------------
-- 화면에 나온 사용자들의 칭호·칭호 모양·말풍선을 한 번에 돌려줍니다. 나를 차단했거나 내가 차단한 사람은 뺍니다.
create function runspot_private.user_badges(user_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if user_ids is null or cardinality(user_ids) > 100 then
    raise exception '사용자는 한 번에 100명까지 조회할 수 있어요.' using errcode='22023';
  end if;
  return (select coalesce(jsonb_object_agg(u.id,jsonb_build_object(
      'title',(select c.title from runspot_private.title_choices c
        where c.user_id=u.id and runspot_private.title_earned(u.id,c.title)),
      'title_style',(select e.item from runspot_private.equipped_cosmetics e where e.user_id=u.id and e.slot='title_style'),
      'chat_bubble',(select e.item from runspot_private.equipped_cosmetics e where e.user_id=u.id and e.slot='chat_bubble'))),
    '{}'::jsonb)
    from (select distinct unnest(user_ids) as id) u
    where u.id=viewer or runspot_private.board_author_visible(u.id,viewer));
end;
$$;

-- 게시판은 글쓴이 ID를 앱에 주지 않으므로 글 ID로 글쓴이의 칭호·모양을 돌려줍니다.
create function runspot_private.post_author_badges(post_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if post_ids is null or cardinality(post_ids) > 100 then
    raise exception '글은 한 번에 100개까지 조회할 수 있어요.' using errcode='22023';
  end if;
  return (select coalesce(jsonb_object_agg(p.id,jsonb_build_object(
      'title',(select c.title from runspot_private.title_choices c
        where c.user_id=p.author_id and runspot_private.title_earned(p.author_id,c.title)),
      'title_style',(select e.item from runspot_private.equipped_cosmetics e
        where e.user_id=p.author_id and e.slot='title_style'))),'{}'::jsonb)
    from runspot_private.board_posts p
    where p.id=any(post_ids) and runspot_private.board_post_visible(p.id,viewer));
end;
$$;

-- 6) 크루 정원을 크루별로 계산합니다(기존 함수에서 정원 계산만 바꿉니다) --------
create or replace function runspot_private.crew_item_json(crew runspot_private.crews,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',crew.id,'name',crew.name,'description',crew.description,
    'icon',crew.icon,'is_owner',crew.owner_id=viewer,'created_at',crew.created_at,
    'size_limit',runspot_private.crew_size_limit(crew.id),
    'expanded',exists(select 1 from runspot_private.crew_expansions where crew_id=crew.id),
    'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,
        'nickname',coalesce(p.nickname,'닉네임 없음'),'role',m.role,'joined_at',m.joined_at)
        order by m.role desc,m.joined_at,m.user_id),'[]'::jsonb)
      from runspot_private.crew_members m left join public.profiles p on p.id=m.user_id
      where m.crew_id=crew.id and (m.user_id=viewer or runspot_private.board_author_visible(m.user_id,viewer))),
    'pending',(select coalesce(jsonb_agg(i.user_id order by i.created_at),'[]'::jsonb)
      from runspot_private.crew_invites i where crew.owner_id=viewer and i.crew_id=crew.id and i.status='invited'));
$$;

create or replace function runspot_private.invite_to_crew(target uuid,requested_crew uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); crew runspot_private.crews;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록을 확인해 주세요.' using errcode='42501';
  end if;
  select * into crew from runspot_private.crews where id=requested_crew for update;
  if not found or crew.owner_id<>viewer then
    raise exception '크루를 만든 사람만 초대할 수 있습니다.' using errcode='42501';
  end if;
  if target is null or target=viewer or not exists(select 1 from public.friendships f
      where f.user_low=least(viewer,target) and f.user_high=greatest(viewer,target) and f.status='accepted')
    or not runspot_private.board_author_visible(target,viewer) then
    raise exception '친구만 크루원으로 초대할 수 있습니다.' using errcode='42501';
  end if;
  if exists(select 1 from runspot_private.crew_members where crew_id=crew.id and user_id=target) then
    raise exception '이미 이 크루의 크루원이에요.' using errcode='P0001';
  end if;
  if (select count(*) from runspot_private.crew_members where crew_id=crew.id) >= runspot_private.crew_size_limit(crew.id) then
    raise exception '크루원은 최대 %명입니다.',runspot_private.crew_size_limit(crew.id) using errcode='P0001';
  end if;
  if exists(select 1 from runspot_private.crew_invites where crew_id=crew.id and user_id=target and status='invited') then
    return runspot_private.crew_json(viewer);
  end if;
  if (select count(*) from runspot_private.crew_invites where invited_by=viewer
      and created_at > now()-interval '1 hour') >= 30 then
    raise exception '크루 초대는 한 시간에 30번까지 가능합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.crew_invites(crew_id,user_id,invited_by) values(crew.id,target,viewer)
  on conflict(crew_id,user_id) do update set status='invited',invited_by=viewer,created_at=now(),responded_at=null;
  insert into runspot_private.notifications(recipient_id,actor_id,kind,crew_id)
  values(target,viewer,'crew_invite',crew.id)
  on conflict (crew_id,recipient_id) where kind='crew_invite'
  do update set actor_id=excluded.actor_id,created_at=now(),read_at=null;
  return runspot_private.crew_json(viewer);
end;
$$;

create or replace function runspot_private.respond_crew_invite(requested_crew uuid,accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); invite runspot_private.crew_invites;
begin
  if accept is null then raise exception '응답을 확인해 주세요.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crew:'||viewer::text,0));
  perform 1 from runspot_private.crews where id=requested_crew for update;
  select * into invite from runspot_private.crew_invites
    where crew_id=requested_crew and user_id=viewer for update;
  if not found or invite.status<>'invited' then
    raise exception '대기 중인 크루 초대만 응답할 수 있습니다.' using errcode='P0001';
  end if;
  if accept then
    if not runspot_private.can_interact() then
      raise exception '이메일 인증과 닉네임 등록 후 크루에 참여할 수 있습니다.' using errcode='42501';
    end if;
    if (select count(*) from runspot_private.crew_members where user_id=viewer)
        >= runspot_private.crews_per_user_limit() then
      raise exception '크루는 한 사람당 10개까지 가입할 수 있어요.' using errcode='P0001';
    end if;
    if (select count(*) from runspot_private.crew_members where crew_id=requested_crew)
        >= runspot_private.crew_size_limit(requested_crew) then
      raise exception '크루 인원이 가득 찼어요.' using errcode='P0001';
    end if;
    insert into runspot_private.crew_members(user_id,crew_id,role) values(viewer,requested_crew,'member')
    on conflict do nothing;
  end if;
  update runspot_private.crew_invites set status=case when accept then 'accepted' else 'declined' end,
    responded_at=now() where crew_id=requested_crew and user_id=viewer;
  return runspot_private.crew_json(viewer);
end;
$$;


-- 7) 앱이 부르는 함수 -----------------------------------------------------------
create function public.my_titles() returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.my_titles(); $$;
create function public.set_title(requested text) returns jsonb language sql security invoker set search_path=''
as $$ select runspot_private.set_title(requested); $$;
create function public.buy_cosmetic(requested_item text) returns jsonb language sql security invoker set search_path=''
as $$ select runspot_private.buy_cosmetic(requested_item); $$;
create function public.equip_cosmetic(requested_slot text,requested_item text) returns jsonb language sql
security invoker set search_path=''
as $$ select runspot_private.equip_cosmetic(requested_slot,requested_item); $$;
create function public.expand_crew(requested_crew uuid) returns jsonb language sql security invoker set search_path=''
as $$ select runspot_private.expand_crew(requested_crew); $$;
create function public.user_badges(user_ids uuid[]) returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.user_badges(user_ids); $$;
create function public.post_author_badges(post_ids uuid[]) returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.post_author_badges(post_ids); $$;
revoke all on function runspot_private.cosmetic_slot(text),runspot_private.cosmetic_price(text),
  runspot_private.crew_expansion_price(),runspot_private.crew_size_limit(uuid),
  runspot_private.my_titles(),runspot_private.set_title(text),runspot_private.buy_cosmetic(text),
  runspot_private.equip_cosmetic(text,text),runspot_private.expand_crew(uuid),runspot_private.user_badges(uuid[]),
  runspot_private.post_author_badges(uuid[]),public.post_author_badges(uuid[]),
  public.my_titles(),public.set_title(text),public.buy_cosmetic(text),public.equip_cosmetic(text,text),
  public.expand_crew(uuid),public.user_badges(uuid[]) from public,anon,authenticated;
grant execute on function runspot_private.my_titles(),runspot_private.set_title(text),runspot_private.buy_cosmetic(text),
  runspot_private.equip_cosmetic(text,text),runspot_private.expand_crew(uuid),runspot_private.user_badges(uuid[]),
  runspot_private.post_author_badges(uuid[]),public.post_author_badges(uuid[]),
  public.my_titles(),public.set_title(text),public.buy_cosmetic(text),public.equip_cosmetic(text,text),
  public.expand_crew(uuid),public.user_badges(uuid[]) to authenticated;
notify pgrst,'reload schema';
