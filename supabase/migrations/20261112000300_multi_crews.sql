-- 한 사람이 여러 크루에 가입하고 여러 크루를 만들 수 있게 합니다. 한 사람당 최대 10개 크루입니다.
alter table runspot_private.crews drop constraint crews_owner_id_key;
create index crews_owner on runspot_private.crews(owner_id);
alter table runspot_private.crew_members drop constraint crew_members_pkey;
alter table runspot_private.crew_members add primary key (crew_id,user_id);
create index crew_members_user on runspot_private.crew_members(user_id);

create function runspot_private.crews_per_user_limit()
returns integer language sql immutable set search_path = '' as $$ select 10; $$;

-- 크루 하나의 정보입니다. 크루장에게만 대기 중 초대를 보여줍니다.
create function runspot_private.crew_item_json(crew runspot_private.crews,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',crew.id,'name',crew.name,'description',crew.description,
    'icon',crew.icon,'is_owner',crew.owner_id=viewer,'created_at',crew.created_at,
    'size_limit',runspot_private.crew_size_limit(),
    'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,
        'nickname',coalesce(p.nickname,'닉네임 없음'),'role',m.role,'joined_at',m.joined_at)
        order by m.role desc,m.joined_at,m.user_id),'[]'::jsonb)
      from runspot_private.crew_members m left join public.profiles p on p.id=m.user_id
      where m.crew_id=crew.id and (m.user_id=viewer or runspot_private.board_author_visible(m.user_id,viewer))),
    'pending',(select coalesce(jsonb_agg(i.user_id order by i.created_at),'[]'::jsonb)
      from runspot_private.crew_invites i where crew.owner_id=viewer and i.crew_id=crew.id and i.status='invited'));
$$;

-- 내가 속한 모든 크루(가입 순)와 내가 받은 초대를 돌려줍니다.
-- 이전 앱이 쓰던 'crew'에는 가장 먼저 가입한 크루를 그대로 넣습니다.
create or replace function runspot_private.crew_json(viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with mine as (
    select c as crew, m.joined_at from runspot_private.crews c
    join runspot_private.crew_members m on m.crew_id=c.id where m.user_id=viewer
  ), listed as (
    select coalesce(jsonb_agg(runspot_private.crew_item_json(mine.crew,viewer)
      order by mine.joined_at,(mine.crew).id),'[]'::jsonb) as crews from mine
  )
  select jsonb_build_object(
    'crews',listed.crews,
    'crew',listed.crews->0,
    'crew_limit',runspot_private.crews_per_user_limit(),
    'invites',(select coalesce(jsonb_agg(jsonb_build_object('crew_id',c.id,'name',c.name,
        'description',c.description,'icon',c.icon,'inviter',coalesce(p.nickname,'닉네임 없음'),
        'created_at',i.created_at) order by i.created_at desc),'[]'::jsonb)
      from runspot_private.crew_invites i join runspot_private.crews c on c.id=i.crew_id
      left join public.profiles p on p.id=i.invited_by
      where i.user_id=viewer and i.status='invited'
        and runspot_private.board_author_visible(i.invited_by,viewer)))
  from listed;
$$;

-- 이미 다른 크루에 속해 있어도 크루를 더 만들 수 있습니다. 한 사람당 크루 수만 제한합니다.
create or replace function runspot_private.create_crew(requested_name text,requested_description text,requested_icon text)
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
  if (select count(*) from runspot_private.crew_members where user_id=viewer)
      >= runspot_private.crews_per_user_limit() then
    raise exception '크루는 한 사람당 10개까지 가입할 수 있어요.' using errcode='P0001';
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

-- 초대할 크루를 고릅니다. 그 크루의 크루장만, 그 크루에 아직 없는 친구만 초대합니다.
drop function public.invite_to_crew(uuid);
drop function runspot_private.invite_to_crew(uuid);
create function runspot_private.invite_to_crew(target uuid,requested_crew uuid)
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
  insert into runspot_private.crew_invites(crew_id,user_id,invited_by) values(crew.id,target,viewer)
  on conflict(crew_id,user_id) do update set status='invited',invited_by=viewer,created_at=now(),responded_at=null;
  insert into runspot_private.notifications(recipient_id,actor_id,kind,crew_id)
  values(target,viewer,'crew_invite',crew.id)
  on conflict (crew_id,recipient_id) where kind='crew_invite'
  do update set actor_id=excluded.actor_id,created_at=now(),read_at=null;
  return runspot_private.crew_json(viewer);
end;
$$;
create function public.invite_to_crew(target uuid,requested_crew uuid) returns jsonb language sql
security invoker set search_path = ''
as $$ select runspot_private.invite_to_crew(target,requested_crew); $$;

-- 다른 크루에 속해 있어도 초대를 수락할 수 있습니다. 한 사람당 크루 수만 제한합니다.
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
        >= runspot_private.crew_size_limit() then
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

-- 다른 크루에 속해 있어도 크루 초대 알림에서 응답할 수 있습니다.
create or replace function runspot_private.my_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'post_id',x.post_id,
      'post_title',p.title,'nickname',coalesce(pr.nickname,'닉네임 없음'),
      'comment',left(c.body,80),'created_at',x.created_at,'read',x.read_at is not null,
      'group_id',x.group_id,'crew_id',x.crew_id,'crew_name',cr.name,
      'invite_status',coalesce(m.status,ci.status),
      'can_respond',(x.kind='group_invite' and m.status='invited' and g.state='lobby' and g.expires_at>now())
        or (x.kind='crew_invite' and ci.status='invited'))
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

revoke all on function runspot_private.crews_per_user_limit(),
  runspot_private.crew_item_json(runspot_private.crews,uuid),
  runspot_private.invite_to_crew(uuid,uuid),public.invite_to_crew(uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function runspot_private.invite_to_crew(uuid,uuid),public.invite_to_crew(uuid,uuid)
  to authenticated;
notify pgrst,'reload schema';
