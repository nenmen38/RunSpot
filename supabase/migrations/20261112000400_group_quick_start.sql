-- 함께 달리기: 친구가 초대를 수락하면 방장이 바로 출발할 수 있게 GPS 준비 확인을 없애고,
-- 방장이 그룹을 취소하면 기록에 남기지 않고 지웁니다. 출발 시각 맞춤(10초 카운트다운)은 그대로입니다.
create or replace function runspot_private.group_action(requested_group uuid,operation text,target_id uuid,client_id uuid)
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
    -- 취소한 그룹은 기록에 남기지 않고 지웁니다. 참여자 목록과 초대 알림도 함께 지워집니다.
    delete from runspot_private.running_groups where id=g.id;
    return g.id;
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
      -- 초대받은 친구가 한 명이라도 수락하면 바로 출발할 수 있습니다. 위치는 출발 카운트다운 동안 각 앱이 잡습니다.
      if (select count(*) from runspot_private.running_group_members where group_id=g.id and status='accepted')<2 then
        raise exception '초대한 친구가 수락하면 출발할 수 있어요.' using errcode='P0001'; end if;
      if exists(select 1 from runspot_private.running_group_members m where m.group_id=g.id and m.status='accepted'
          and (not runspot_private.is_active(m.user_id) or not runspot_private.email_verified(m.user_id))) then
        raise exception '참여자의 계정 상태를 확인해 주세요.' using errcode='P0001'; end if;
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

create or replace function runspot_private.group_dashboard()
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
            'distance_m',case when mine.status in ('accepted','finished') and m.status='finished' and not r.review_pending and r.integrity_status<>'rejected' then r.distance_m end,
            'duration_sec',case when mine.status in ('accepted','finished') and m.status='finished' and not r.review_pending and r.integrity_status<>'rejected' then r.duration_sec end)
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
      -- 취소된 그룹과 취소된 초대는 목록에 남기지 않습니다.
      where mine.status in ('invited','accepted','finished','left') and g.state<>'cancelled'
        and runspot_private.group_allowed(g.id)
      order by g.created_at desc,g.id limit 20
    ) recent_groups));
end;
$$;

-- 이미 취소된 그룹도 기록에서 지웁니다.
delete from runspot_private.running_groups where state='cancelled';

-- 알림창의 "모두 지우기"입니다. 받은 알림을 모두 지웁니다. 대기 중인 초대는 함께 달리기·크루 화면에서 계속 응답할 수 있습니다.
create function runspot_private.clear_my_notifications()
returns integer language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); removed integer;
begin
  delete from runspot_private.notifications where recipient_id=viewer;
  get diagnostics removed = row_count;
  return removed;
end;
$$;
create function public.clear_my_notifications() returns integer language sql security invoker set search_path = ''
as $$ select runspot_private.clear_my_notifications(); $$;
revoke all on function runspot_private.clear_my_notifications(),public.clear_my_notifications()
  from public,anon,authenticated;
grant execute on function runspot_private.clear_my_notifications(),public.clear_my_notifications() to authenticated;
notify pgrst,'reload schema';
