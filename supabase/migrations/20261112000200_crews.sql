-- 크루: 코인으로 산 크루 생성권으로 크루를 만들고, 크루를 만든 사람이 친구를 크루원으로 초대합니다.
-- 한 사람은 한 크루에만 속하며, 모든 확인(코인·친구 관계·인원)은 서버에서 합니다.

create table runspot_private.crews (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 20),
  description text not null default '' check (char_length(description) <= 60),
  icon text not null check (icon in ('bolt','flame','mountain','wave','star')),
  created_at timestamptz not null default now()
);
-- 대소문자만 다른 같은 이름은 쓰지 않습니다.
create unique index crews_name on runspot_private.crews(lower(name));

-- 사용자 ID가 기본 키라 한 사람은 한 크루에만 속합니다.
create table runspot_private.crew_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  crew_id uuid not null references runspot_private.crews(id) on delete cascade,
  role text not null check (role in ('owner','member')),
  joined_at timestamptz not null default now()
);
create index crew_members_crew on runspot_private.crew_members(crew_id,joined_at);

create table runspot_private.crew_invites (
  crew_id uuid not null references runspot_private.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'invited' check (status in ('invited','accepted','declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key(crew_id,user_id)
);
create index crew_invites_user on runspot_private.crew_invites(user_id) where status='invited';

-- 크루 생성권입니다. 사용하면 만든 크루와 연결하고, 산 가격은 코인 잔액에서 뺍니다.
create table runspot_private.crew_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  coins integer not null check (coins >= 0),
  purchased_at timestamptz not null default now(),
  used_at timestamptz,
  crew_id uuid references runspot_private.crews(id) on delete set null
);
create index crew_tickets_user on runspot_private.crew_tickets(user_id);

alter table runspot_private.crews enable row level security;
alter table runspot_private.crew_members enable row level security;
alter table runspot_private.crew_invites enable row level security;
alter table runspot_private.crew_tickets enable row level security;
revoke all on runspot_private.crews,runspot_private.crew_members,runspot_private.crew_invites,
  runspot_private.crew_tickets from public,anon,authenticated;

-- 크루 생성권 가격입니다. 1,100원 = 100코인 기준으로 약 7,040원입니다.
create function runspot_private.crew_ticket_price()
returns integer language sql immutable set search_path = '' as $$ select 640; $$;

create function runspot_private.crew_size_limit()
returns integer language sql immutable set search_path = '' as $$ select 30; $$;

-- 잔액 계산에 크루 생성권 구매를 더합니다.
create or replace function runspot_private.coin_balance(target uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select runspot_private.level_coins(runspot_private.user_level(target))
    + coalesce((select sum(coins) from runspot_private.coin_purchases
        where user_id=target and refunded_at is null),0)::integer
    + coalesce((select sum(coins) from runspot_private.coin_grants where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.owned_frames where user_id=target),0)::integer
    - coalesce((select sum(coins) from runspot_private.crew_tickets where user_id=target),0)::integer;
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
      'aura',runspot_private.frame_price('aura'),'crew_ticket',runspot_private.crew_ticket_price()),
    'owned',(select coalesce(jsonb_agg(frame order by frame),'[]'::jsonb)
      from runspot_private.owned_frames where user_id=target),
    'equipped',(select frame from runspot_private.frame_settings where user_id=target),
    'color',coalesce((select color from runspot_private.frame_settings where user_id=target),'#3182F6'),
    'crew_tickets',(select count(*) from runspot_private.crew_tickets where user_id=target and used_at is null),
    'in_crew',exists(select 1 from runspot_private.crew_members where user_id=target))
  from l;
$$;

-- 아직 쓰지 않은 생성권이 있으면 더 사지 않습니다. 한 사람은 한 크루에만 속하기 때문입니다.
create function runspot_private.buy_crew_ticket()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); price integer := runspot_private.crew_ticket_price();
begin
  perform pg_advisory_xact_lock(hashtextextended('coins:'||viewer::text,0));
  if exists(select 1 from runspot_private.crew_tickets where user_id=viewer and used_at is null) then
    raise exception '사용하지 않은 크루 생성권이 이미 있어요.' using errcode='P0001';
  end if;
  if runspot_private.coin_balance(viewer) < price then
    raise exception '코인이 부족합니다.' using errcode='P0001';
  end if;
  insert into runspot_private.crew_tickets(user_id,coins) values(viewer,price);
  return runspot_private.wallet_json(viewer);
end;
$$;

-- 내 크루와 크루원, 내가 받은 초대, 크루장이 보낸 대기 중 초대를 함께 돌려줍니다.
create function runspot_private.crew_json(viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with mine as (select c.* from runspot_private.crews c
    join runspot_private.crew_members m on m.crew_id=c.id where m.user_id=viewer)
  select jsonb_build_object(
    'crew',(select jsonb_build_object('id',mine.id,'name',mine.name,'description',mine.description,
      'icon',mine.icon,'is_owner',mine.owner_id=viewer,'created_at',mine.created_at,
      'size_limit',runspot_private.crew_size_limit(),
      'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,
          'nickname',coalesce(p.nickname,'닉네임 없음'),'role',m.role,'joined_at',m.joined_at)
          order by m.role desc,m.joined_at,m.user_id),'[]'::jsonb)
        from runspot_private.crew_members m left join public.profiles p on p.id=m.user_id
        where m.crew_id=mine.id and (m.user_id=viewer or runspot_private.board_author_visible(m.user_id,viewer))),
      'pending',(select coalesce(jsonb_agg(i.user_id order by i.created_at),'[]'::jsonb)
        from runspot_private.crew_invites i where mine.owner_id=viewer and i.crew_id=mine.id and i.status='invited'))
      from mine),
    'invites',(select coalesce(jsonb_agg(jsonb_build_object('crew_id',c.id,'name',c.name,
        'description',c.description,'icon',c.icon,'inviter',coalesce(p.nickname,'닉네임 없음'),
        'created_at',i.created_at) order by i.created_at desc),'[]'::jsonb)
      from runspot_private.crew_invites i join runspot_private.crews c on c.id=i.crew_id
      left join public.profiles p on p.id=i.invited_by
      where i.user_id=viewer and i.status='invited'
        and runspot_private.board_author_visible(i.invited_by,viewer)));
$$;

create function runspot_private.my_crew()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  return runspot_private.crew_json(runspot_private.require_board_viewer());
end;
$$;

-- 생성권 하나를 써서 크루를 만듭니다. 만든 사람이 크루장이 됩니다.
create function runspot_private.create_crew(requested_name text,requested_description text,requested_icon text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  name_value text := btrim(requested_name);
  description_value text := coalesce(btrim(requested_description),'');
  ticket uuid;
  created uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 크루를 만들 수 있습니다.' using errcode='42501';
  end if;
  if name_value is null or char_length(name_value) not between 2 and 20 then
    raise exception '크루 이름은 2~20자로 입력해 주세요.' using errcode='22023';
  end if;
  if char_length(description_value) > 60 then
    raise exception '크루 설명은 60자 이내로 입력해 주세요.' using errcode='22023';
  end if;
  if requested_icon is null or requested_icon not in ('bolt','flame','mountain','wave','star') then
    raise exception '크루 아이콘을 골라 주세요.' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('crew:'||viewer::text,0));
  if exists(select 1 from runspot_private.crew_members where user_id=viewer) then
    raise exception '이미 크루에 속해 있어요.' using errcode='P0001';
  end if;
  select id into ticket from runspot_private.crew_tickets
    where user_id=viewer and used_at is null order by purchased_at limit 1 for update;
  if ticket is null then
    raise exception '크루 생성권이 필요합니다.' using errcode='P0001';
  end if;
  begin
    insert into runspot_private.crews(owner_id,name,description,icon)
    values(viewer,name_value,description_value,requested_icon) returning id into created;
  exception when unique_violation then
    raise exception '이미 쓰고 있는 크루 이름이에요.' using errcode='P0001';
  end;
  insert into runspot_private.crew_members(user_id,crew_id,role) values(viewer,created,'owner');
  update runspot_private.crew_tickets set used_at=now(),crew_id=created where id=ticket;
  return runspot_private.crew_json(viewer);
end;
$$;

-- 크루장만 친구를 초대합니다. 다른 크루에 속한 친구, 차단 관계, 가득 찬 크루는 초대하지 않습니다.
create function runspot_private.invite_to_crew(target uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); crew runspot_private.crews;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록을 확인해 주세요.' using errcode='42501';
  end if;
  select * into crew from runspot_private.crews where owner_id=viewer for update;
  if not found then raise exception '크루를 만든 사람만 초대할 수 있습니다.' using errcode='42501'; end if;
  if target is null or target=viewer or not exists(select 1 from public.friendships f
      where f.user_low=least(viewer,target) and f.user_high=greatest(viewer,target) and f.status='accepted')
    or not runspot_private.board_author_visible(target,viewer) then
    raise exception '친구만 크루원으로 초대할 수 있습니다.' using errcode='42501';
  end if;
  if exists(select 1 from runspot_private.crew_members where user_id=target) then
    raise exception '이미 크루에 속한 친구예요.' using errcode='P0001';
  end if;
  if (select count(*) from runspot_private.crew_members where crew_id=crew.id) >= runspot_private.crew_size_limit() then
    raise exception '크루원은 최대 30명입니다.' using errcode='P0001';
  end if;
  if exists(select 1 from runspot_private.crew_invites where crew_id=crew.id and user_id=target and status='invited') then
    return runspot_private.crew_json(viewer);
  end if;
  if (select count(*) from runspot_private.crew_invites where invited_by=viewer
      and created_at > now()-interval '1 hour') >= 30 then
    raise exception '크루 초대는 한 시간에 30번까지 가능합니다.' using errcode='P0001';
  end if;
  -- 거절했던 친구도 다시 초대할 수 있습니다. 알림은 새 초대로 다시 띄웁니다.
  insert into runspot_private.crew_invites(crew_id,user_id,invited_by) values(crew.id,target,viewer)
  on conflict(crew_id,user_id) do update set status='invited',invited_by=viewer,created_at=now(),responded_at=null;
  insert into runspot_private.notifications(recipient_id,actor_id,kind,crew_id)
  values(target,viewer,'crew_invite',crew.id)
  on conflict (crew_id,recipient_id) where kind='crew_invite'
  do update set actor_id=excluded.actor_id,created_at=now(),read_at=null;
  return runspot_private.crew_json(viewer);
end;
$$;

create function runspot_private.respond_crew_invite(requested_crew uuid,accept boolean)
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
    if exists(select 1 from runspot_private.crew_members where user_id=viewer) then
      raise exception '이미 크루에 속해 있어요.' using errcode='P0001';
    end if;
    if (select count(*) from runspot_private.crew_members where crew_id=requested_crew)
        >= runspot_private.crew_size_limit() then
      raise exception '크루 인원이 가득 찼어요.' using errcode='P0001';
    end if;
    insert into runspot_private.crew_members(user_id,crew_id,role) values(viewer,requested_crew,'member');
  end if;
  update runspot_private.crew_invites set status=case when accept then 'accepted' else 'declined' end,
    responded_at=now() where crew_id=requested_crew and user_id=viewer;
  return runspot_private.crew_json(viewer);
end;
$$;

-- 확성기 알림에 크루 초대를 더합니다.
alter table runspot_private.notifications
  add column crew_id uuid references runspot_private.crews(id) on delete cascade,
  drop constraint notifications_kind_check,
  drop constraint notifications_target_check,
  add constraint notifications_kind_check check (kind in ('like','comment','reply','group_invite','crew_invite')),
  add constraint notifications_target_check check (case kind
    when 'group_invite' then group_id is not null and post_id is null and crew_id is null
    when 'crew_invite' then crew_id is not null and post_id is null and group_id is null
    else post_id is not null and group_id is null and crew_id is null end);
create unique index notifications_crew_invite_once on runspot_private.notifications(crew_id,recipient_id)
  where kind='crew_invite';

create or replace function runspot_private.notification_visible(n runspot_private.notifications,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.board_author_visible(n.actor_id,viewer) and case n.kind
    when 'group_invite' then exists(select 1 from runspot_private.running_group_members m
      where m.group_id=n.group_id and m.user_id=viewer)
    when 'crew_invite' then exists(select 1 from runspot_private.crew_invites i
      where i.crew_id=n.crew_id and i.user_id=viewer)
    else runspot_private.board_post_visible(n.post_id,viewer)
      and (n.kind<>'like' or exists(select 1 from runspot_private.board_likes l
        where l.post_id=n.post_id and l.user_id=n.actor_id)) end;
$$;

create or replace function runspot_private.my_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
  in_crew boolean := exists(select 1 from runspot_private.crew_members where user_id=viewer);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'post_id',x.post_id,
      'post_title',p.title,'nickname',coalesce(pr.nickname,'닉네임 없음'),
      'comment',left(c.body,80),'created_at',x.created_at,'read',x.read_at is not null,
      'group_id',x.group_id,'crew_id',x.crew_id,'crew_name',cr.name,
      'invite_status',coalesce(m.status,ci.status),
      'can_respond',(x.kind='group_invite' and m.status='invited' and g.state='lobby' and g.expires_at>now())
        or (x.kind='crew_invite' and ci.status='invited' and not in_crew))
      order by x.created_at desc,x.id desc),'[]'::jsonb)
    from (select * from runspot_private.notifications n where n.recipient_id=viewer
      and runspot_private.notification_visible(n,viewer) order by n.created_at desc,n.id desc limit 50) x
    left join runspot_private.board_posts p on p.id=x.post_id
    left join runspot_private.board_comments c on c.id=x.comment_id
    left join runspot_private.running_groups g on g.id=x.group_id
    left join runspot_private.running_group_members m on m.group_id=x.group_id and m.user_id=viewer
    left join runspot_private.crews cr on cr.id=x.crew_id
    left join runspot_private.crew_invites ci on ci.crew_id=x.crew_id and ci.user_id=viewer
    left join public.profiles pr on pr.id=x.actor_id);
end;
$$;

create function public.buy_crew_ticket() returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.buy_crew_ticket(); $$;
create function public.my_crew() returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_crew(); $$;
create function public.create_crew(requested_name text,requested_description text,requested_icon text)
returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.create_crew(requested_name,requested_description,requested_icon); $$;
create function public.invite_to_crew(target uuid) returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.invite_to_crew(target); $$;
create function public.respond_crew_invite(requested_crew uuid,accept boolean) returns jsonb language sql
security invoker set search_path = ''
as $$ select runspot_private.respond_crew_invite(requested_crew,accept); $$;

revoke all on function runspot_private.crew_ticket_price(),runspot_private.crew_size_limit(),
  runspot_private.crew_json(uuid),runspot_private.buy_crew_ticket(),runspot_private.my_crew(),
  runspot_private.create_crew(text,text,text),runspot_private.invite_to_crew(uuid),
  runspot_private.respond_crew_invite(uuid,boolean),
  public.buy_crew_ticket(),public.my_crew(),public.create_crew(text,text,text),
  public.invite_to_crew(uuid),public.respond_crew_invite(uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function runspot_private.buy_crew_ticket(),runspot_private.my_crew(),
  runspot_private.create_crew(text,text,text),runspot_private.invite_to_crew(uuid),
  runspot_private.respond_crew_invite(uuid,boolean),
  public.buy_crew_ticket(),public.my_crew(),public.create_crew(text,text,text),
  public.invite_to_crew(uuid),public.respond_crew_invite(uuid,boolean) to authenticated;
notify pgrst,'reload schema';
