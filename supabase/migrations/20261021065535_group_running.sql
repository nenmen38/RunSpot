-- 그룹은 동의한 참여자에게만 닉네임과 완료 측정값을 공유하며 개인 경로는 공유하지 않습니다.
create table runspot_private.running_groups (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  state text not null default 'lobby' check(state in ('lobby','scheduled','finished','cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 minutes',
  starts_at timestamptz
);
create index running_groups_host on runspot_private.running_groups(host_id,created_at);
create table runspot_private.running_group_members (
  group_id uuid not null references runspot_private.running_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check(status in ('invited','accepted','declined','cancelled','left','finished')),
  ready_at timestamptz,
  client_run_id uuid,
  run_id uuid references public.runs(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(group_id,user_id)
);
create index running_group_members_owner on runspot_private.running_group_members(user_id,created_at);
create unique index running_group_members_run on runspot_private.running_group_members(user_id,client_run_id) where client_run_id is not null;
alter table runspot_private.running_groups enable row level security;
alter table runspot_private.running_group_members enable row level security;
revoke all on runspot_private.running_groups,runspot_private.running_group_members from public,anon,authenticated;
grant all on runspot_private.running_groups,runspot_private.running_group_members to service_role;

create function runspot_private.group_allowed(requested_group uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and runspot_private.is_active(auth.uid()) and exists(
    select 1 from runspot_private.running_group_members m join runspot_private.running_groups g on g.id=m.group_id
    where g.id=requested_group and m.user_id=auth.uid() and m.status in ('invited','accepted','finished','left','cancelled')
      and not exists(select 1 from runspot_private.blocks b
        where (b.blocker_id=auth.uid() and b.blocked_id=g.host_id) or (b.blocked_id=auth.uid() and b.blocker_id=g.host_id)));
$$;

create function runspot_private.group_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return jsonb_build_object('server_now',clock_timestamp(),'groups',(
    select coalesce(jsonb_agg(entry order by created_at desc,id),'[]'::jsonb) from (
      select g.created_at,g.id,jsonb_build_object('id',g.id,'host_id',g.host_id,'starts_at',g.starts_at,
        'state',case when g.state in ('lobby','scheduled') and g.expires_at<=now() then 'expired'
          when g.state='scheduled' and g.starts_at<=now() then 'running' else g.state end,
        'my_status',mine.status,'members',(
          select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'nickname',coalesce(p.nickname,'닉네임 없음'),
            'status',m.status,'ready',m.ready_at>now()-interval '30 seconds','client_run_id',case when m.user_id=auth.uid() then m.client_run_id end,
            'distance_m',case when mine.status in ('accepted','finished') and m.status='finished' and r.integrity_status<>'rejected' then r.distance_m end,
            'duration_sec',case when mine.status in ('accepted','finished') and m.status='finished' and r.integrity_status<>'rejected' then r.duration_sec end)
            order by m.created_at,m.user_id),'[]'::jsonb)
          from runspot_private.running_group_members m join public.profiles p on p.id=m.user_id
          left join public.runs r on r.id=m.run_id
          where m.group_id=g.id and runspot_private.is_active(m.user_id)
            and (m.user_id=auth.uid() or m.user_id=g.host_id or g.host_id=auth.uid()
              or (mine.status in ('accepted','finished') and m.status in ('accepted','finished')))
            and not exists(select 1 from runspot_private.blocks b where
              (b.blocker_id=auth.uid() and b.blocked_id=m.user_id) or (b.blocked_id=auth.uid() and b.blocker_id=m.user_id))
        )) entry
      from runspot_private.running_groups g join runspot_private.running_group_members mine on mine.group_id=g.id and mine.user_id=auth.uid()
      where mine.status in ('invited','accepted','finished','left','cancelled') and runspot_private.group_allowed(g.id)
      order by g.created_at desc,g.id limit 20
    ) recent_groups));
end;
$$;

create function runspot_private.group_action(requested_group uuid,operation text,target_id uuid,client_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare viewer uuid:=auth.uid(); g runspot_private.running_groups; mine runspot_private.running_group_members; result uuid;
begin
  if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인 상태를 확인해 주세요.' using errcode='42501'; end if;
  if operation is null or operation not in ('create','invite','accept','reject','cancel_invite','leave','cancel','ready','unready','start','join_run') then
    raise exception '그룹 작업을 확인해 주세요.' using errcode='22023';
  end if;
  -- 친구·차단 변경과 같은 순서로 모든 참여자 프로필을 잠근 후 그룹을 잠급니다.
  perform 1 from auth.users where id in (select user_id from runspot_private.running_group_members where group_id=requested_group)
    or id in (viewer,target_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (select user_id from runspot_private.running_group_members where group_id=requested_group)
    or user_id in (viewer,target_id) order by user_id for share;
  perform 1 from public.profiles where id in (select user_id from runspot_private.running_group_members where group_id=requested_group)
    or id in (viewer,target_id) order by id for update;
  if not runspot_private.is_active(viewer) then raise exception '계정 상태를 확인해 주세요.' using errcode='42501'; end if;
  if operation in ('create','accept') and exists(select 1 from runspot_private.running_group_members m
    join runspot_private.running_groups other_group on other_group.id=m.group_id
    where m.user_id=viewer and m.status='accepted' and other_group.state in ('lobby','scheduled')
      and other_group.expires_at>now() and other_group.id is distinct from requested_group) then
    raise exception '참여 중인 그룹을 먼저 종료하거나 나가 주세요.' using errcode='P0001';
  end if;
  if operation='create' then
    if not runspot_private.can_interact() then raise exception '이메일 인증과 닉네임 등록이 필요합니다.' using errcode='42501'; end if;
    if (select count(*) from runspot_private.running_groups where host_id=viewer and created_at>now()-interval '1 hour')>=5 then
      raise exception '그룹은 한 시간에 5개까지 만들 수 있습니다.' using errcode='P0001'; end if;
    insert into runspot_private.running_groups(host_id) values(viewer) returning id into result;
    insert into runspot_private.running_group_members(group_id,user_id,status) values(result,viewer,'accepted');
    return result;
  end if;
  if not runspot_private.group_allowed(requested_group) then raise exception '그룹에 접근할 수 없습니다.' using errcode='42501'; end if;
  select * into g from runspot_private.running_groups where id=requested_group for update;
  select * into mine from runspot_private.running_group_members where group_id=requested_group and user_id=viewer for update;
  if operation='join_run' and client_id is not null and mine.client_run_id=client_id then return g.id; end if;
  if operation='unready' then
    update runspot_private.running_group_members set ready_at=null where group_id=g.id and user_id=viewer;
    return g.id;
  end if;
  if g.state in ('finished','cancelled') or g.expires_at<=now() then raise exception '종료되거나 만료된 그룹입니다.' using errcode='P0001'; end if;
  if operation='cancel' then
    if g.host_id<>viewer then raise exception '방장만 취소할 수 있습니다.' using errcode='42501'; end if;
    update runspot_private.running_groups set state='cancelled' where id=g.id;
  elsif operation='leave' then
    if viewer=g.host_id or mine.status<>'accepted' then raise exception '참여 상태를 확인해 주세요.' using errcode='42501'; end if;
    update runspot_private.running_group_members set status='left',ready_at=null where group_id=g.id and user_id=viewer;
  elsif operation in ('accept','reject') then
    if mine.status='accepted' and operation='accept' then return g.id; end if;
    if g.state<>'lobby' or mine.status<>'invited' then raise exception '대기 중인 초대만 응답할 수 있습니다.' using errcode='P0001'; end if;
    if operation='accept' and (not runspot_private.can_interact() or not exists(select 1 from public.friendships f
      where f.user_low=least(viewer,g.host_id) and f.user_high=greatest(viewer,g.host_id) and f.status='accepted')) then
      raise exception '인증과 친구 관계를 확인해 주세요.' using errcode='42501'; end if;
    update runspot_private.running_group_members set status=case when operation='accept' then 'accepted' else 'declined' end
      where group_id=g.id and user_id=viewer;
  elsif operation in ('invite','cancel_invite') then
    if viewer<>g.host_id then raise exception '방장만 초대를 관리할 수 있습니다.' using errcode='42501'; end if;
    if g.state<>'lobby' or target_id is null or target_id=viewer then raise exception '초대 대상과 그룹 상태를 확인해 주세요.' using errcode='22023'; end if;
    if operation='cancel_invite' then
      update runspot_private.running_group_members set status='cancelled' where group_id=g.id and user_id=target_id and status='invited';
    else
      if not runspot_private.can_interact() or not runspot_private.is_active(target_id) or not runspot_private.email_verified(target_id)
        or not exists(select 1 from public.friendships where user_low=least(viewer,target_id) and user_high=greatest(viewer,target_id) and status='accepted')
        or exists(select 1 from runspot_private.blocks b join runspot_private.running_group_members m on m.group_id=g.id
          where (b.blocker_id=target_id and b.blocked_id=m.user_id) or (b.blocked_id=target_id and b.blocker_id=m.user_id)) then
        raise exception '초대할 수 없는 사용자입니다.' using errcode='42501'; end if;
      if exists(select 1 from runspot_private.running_group_members where group_id=g.id and user_id=target_id) then return g.id; end if;
      if (select count(*) from runspot_private.running_group_members where group_id=g.id)>=8 then
        raise exception '그룹은 방장 포함 최대 8명입니다.' using errcode='P0001'; end if;
      if (select count(*) from runspot_private.running_group_members m join runspot_private.running_groups h on h.id=m.group_id
        where h.host_id=viewer and m.user_id<>viewer and m.created_at>now()-interval '1 hour')>=30 then
        raise exception '그룹 초대는 한 시간에 30번까지 가능합니다.' using errcode='P0001'; end if;
      insert into runspot_private.running_group_members(group_id,user_id,status) values(g.id,target_id,'invited');
    end if;
  elsif operation in ('ready','start','join_run') then
    if mine.status<>'accepted' or not runspot_private.can_interact() then raise exception '참여와 인증 상태를 확인해 주세요.' using errcode='42501'; end if;
    if operation='ready' then
      if g.state<>'lobby' then raise exception '준비 상태를 변경할 수 없습니다.' using errcode='P0001'; end if;
      update runspot_private.running_group_members set ready_at=now() where group_id=g.id and user_id=viewer;
    elsif operation='start' then
      if viewer<>g.host_id then raise exception '방장만 출발을 예약할 수 있습니다.' using errcode='42501'; end if;
      if g.state='scheduled' then return g.id; end if;
      if (select count(*) from runspot_private.running_group_members where group_id=g.id and status='accepted')<2
        or exists(select 1 from runspot_private.running_group_members m where m.group_id=g.id and m.status='accepted'
          and (m.ready_at is null or m.ready_at<=now()-interval '30 seconds' or not runspot_private.is_active(m.user_id)
            or not runspot_private.email_verified(m.user_id))) then
        raise exception '두 명 이상 참여하고 모두 GPS 준비를 완료해야 합니다.' using errcode='P0001'; end if;
      update runspot_private.running_groups set state='scheduled',starts_at=clock_timestamp()+interval '10 seconds',expires_at=clock_timestamp()+interval '24 hours' where id=g.id;
      update runspot_private.running_group_members set status='cancelled' where group_id=g.id and status='invited';
    else
      if g.state<>'scheduled' or now()<g.starts_at-interval '2 seconds' or now()>g.starts_at+interval '60 seconds' or client_id is null then
        raise exception '공동 출발 시간을 놓쳤습니다. 개인 러닝으로 계속해 주세요.' using errcode='P0001'; end if;
      if mine.client_run_id=client_id then return g.id; end if;
      if mine.client_run_id is not null then raise exception '이미 연결된 러닝이 있습니다.' using errcode='P0001'; end if;
      update runspot_private.running_group_members set client_run_id=client_id where group_id=g.id and user_id=viewer;
      -- 느린 출발 연결 응답보다 개인 기록 저장이 먼저 끝난 경우에도 같은 기록을 연결합니다.
      select id into result from public.runs where user_id=viewer and client_run_id=client_id
        and started_at between g.starts_at-interval '1 minute' and g.starts_at+interval '1 minute';
      if result is not null then
        update runspot_private.running_group_members set status='finished',run_id=result where group_id=g.id and user_id=viewer;
        if not exists(select 1 from runspot_private.running_group_members where group_id=g.id and status='accepted') then
          update runspot_private.running_groups set state='finished' where id=g.id;
        end if;
      end if;
    end if;
  end if;
  return g.id;
end;
$$;

create function runspot_private.attach_group_result()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_group uuid;
begin
  select m.group_id into target_group from runspot_private.running_group_members m join runspot_private.running_groups g on g.id=m.group_id
    where m.user_id=new.user_id and m.client_run_id=new.client_run_id and m.status='accepted' and g.state='scheduled'
      and new.started_at between g.starts_at-interval '1 minute' and g.starts_at+interval '1 minute';
  if target_group is null then return null; end if;
  perform 1 from runspot_private.running_groups where id=target_group for update;
  update runspot_private.running_group_members set status='finished',run_id=new.id where group_id=target_group and user_id=new.user_id;
  if not exists(select 1 from runspot_private.running_group_members where group_id=target_group and status='accepted') then
    update runspot_private.running_groups set state='finished' where id=target_group;
  end if;
  return null;
end;
$$;
create trigger runs_attach_group_result after insert on public.runs for each row execute function runspot_private.attach_group_result();

create function runspot_private.cancel_blocked_groups()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update runspot_private.running_groups g set state='cancelled' where g.state in ('lobby','scheduled')
    and exists(select 1 from runspot_private.running_group_members where group_id=g.id and user_id=new.blocker_id and status in ('accepted','invited'))
    and exists(select 1 from runspot_private.running_group_members where group_id=g.id and user_id=new.blocked_id and status in ('accepted','invited'));
  return null;
end;
$$;
create trigger blocks_cancel_groups after insert on runspot_private.blocks for each row execute function runspot_private.cancel_blocked_groups();
create function public.group_dashboard() returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.group_dashboard(); $$;
create function public.group_action(requested_group uuid,operation text,target_id uuid default null,client_id uuid default null)
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.group_action(requested_group,operation,target_id,client_id); $$;
revoke all on function runspot_private.group_allowed(uuid),runspot_private.group_dashboard(),runspot_private.group_action(uuid,text,uuid,uuid),
  runspot_private.attach_group_result(),runspot_private.cancel_blocked_groups(),public.group_dashboard(),public.group_action(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function runspot_private.group_dashboard(),runspot_private.group_action(uuid,text,uuid,uuid),public.group_dashboard(),public.group_action(uuid,text,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
