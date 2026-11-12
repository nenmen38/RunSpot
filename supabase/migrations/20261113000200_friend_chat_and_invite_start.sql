-- 친구 대화는 당사자만 조회하며 차단·친구 해제 후에는 접근을 차단합니다.
create table runspot_private.friend_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  user_low uuid generated always as (least(sender_id,recipient_id)) stored,
  user_high uuid generated always as (greatest(sender_id,recipient_id)) stored,
  body text not null check (char_length(body) between 1 and 1000 and body ~ '[^[:space:]]'),
  request_id uuid not null,
  unique(sender_id,request_id),
  sent_at timestamptz not null default clock_timestamp(),
  check (sender_id<>recipient_id)
);
alter table runspot_private.friend_messages enable row level security;
revoke all on runspot_private.friend_messages from public, anon, authenticated;
create index friend_messages_pair on runspot_private.friend_messages(user_low,user_high,id desc);
create index friend_messages_recipient on runspot_private.friend_messages(recipient_id);
create index friend_messages_sender_recent on runspot_private.friend_messages(sender_id,sent_at desc);

create function runspot_private.can_chat_with(peer_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and peer_id is not null and peer_id<>auth.uid()
    and runspot_private.can_interact() and runspot_private.is_active(peer_id)
    and runspot_private.email_verified(peer_id)
    and exists(select 1 from public.friendships f
      where f.user_low=least(auth.uid(),peer_id) and f.user_high=greatest(auth.uid(),peer_id) and f.status='accepted')
    and not exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=auth.uid() and b.blocked_id=peer_id)
         or (b.blocker_id=peer_id and b.blocked_id=auth.uid()));
$$;

create function runspot_private.friend_chat_read(peer_id uuid,before_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid:=auth.uid();
begin
  if not runspot_private.can_interact() or
      (peer_id is not null and not runspot_private.can_chat_with(peer_id)) then
    raise exception '대화에 접근할 수 없습니다.' using errcode='42501';
  end if;
  if peer_id is not null then
    return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id desc),'[]'::jsonb)
      from (select id,sender_id,body,sent_at from runspot_private.friend_messages
        where user_low=least(viewer,peer_id) and user_high=greatest(viewer,peer_id)
          and (before_id is null or id<before_id)
        order by id desc limit 50) m);
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(room) order by room.id desc),'[]'::jsonb)
    from (select p.id as peer_id,p.nickname,m.id,m.body,m.sent_at
      from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      cross join lateral (select id,body,sent_at from runspot_private.friend_messages
        where user_low=f.user_low and user_high=f.user_high order by id desc limit 1) m
      where (f.user_low=viewer or f.user_high=viewer) and f.status='accepted'
        and runspot_private.can_chat_with(p.id)
      order by m.id desc) room);
end;
$$;

create function runspot_private.friend_chat_send(peer_id uuid,message_body text,request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); cleaned text:=btrim(message_body);
begin
  if viewer is null or peer_id is null or viewer=peer_id or request_id is null then
    raise exception '대화 상대를 확인해 주세요.' using errcode='42501';
  end if;
  if cleaned is null or char_length(cleaned) not between 1 and 1000 or cleaned !~ '[^[:space:]]' then
    raise exception '메시지는 1~1000자로 입력해 주세요.' using errcode='22023';
  end if;
  -- 친구·차단 작업과 같은 순서로 잠가 권한 검사와 메시지 저장을 보호합니다.
  perform 1 from auth.users where id in (viewer,peer_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (viewer,peer_id) order by user_id for share;
  perform 1 from public.profiles where id in (viewer,peer_id) order by id for update;
  if not runspot_private.can_chat_with(peer_id) then
    raise exception '친구에게만 메시지를 보낼 수 있습니다.' using errcode='42501';
  end if;
  if exists(select 1 from runspot_private.friend_messages m
      where m.sender_id=viewer and m.request_id=friend_chat_send.request_id) then
    if exists(select 1 from runspot_private.friend_messages m
        where m.sender_id=viewer and m.request_id=friend_chat_send.request_id
          and m.recipient_id=peer_id and m.body=cleaned) then
      return;
    end if;
    raise exception '메시지 요청이 이미 사용되었습니다.' using errcode='22023';
  end if;
  if (select count(*) from runspot_private.friend_messages
      where sender_id=viewer and sent_at>clock_timestamp()-interval '1 minute')>=30 then
    raise exception '잠시 후 메시지를 다시 보내 주세요.' using errcode='P0001';
  end if;
  insert into runspot_private.friend_messages(sender_id,recipient_id,body,request_id) values(viewer,peer_id,cleaned,request_id);
end;
$$;

create function public.friend_chat_read(peer_id uuid default null,before_id bigint default null)
returns jsonb language sql stable security invoker set search_path='' as $$
  select runspot_private.friend_chat_read(peer_id,before_id);
$$;
create function public.friend_chat_send(peer_id uuid,message_body text,request_id uuid)
returns void language sql security invoker set search_path='' as $$
  select runspot_private.friend_chat_send(peer_id,message_body,request_id);
$$;
revoke all on function runspot_private.can_chat_with(uuid),
  runspot_private.friend_chat_read(uuid,bigint),runspot_private.friend_chat_send(uuid,text,uuid),
  public.friend_chat_read(uuid,bigint),public.friend_chat_send(uuid,text,uuid) from public,anon,authenticated;
grant execute on function runspot_private.friend_chat_read(uuid,bigint),runspot_private.friend_chat_send(uuid,text,uuid),
  public.friend_chat_read(uuid,bigint),public.friend_chat_send(uuid,text,uuid) to authenticated;

-- 사용자 메뉴에서 만든 초대는 수락과 공동 출발 예약을 같은 트랜잭션에서 처리합니다.
alter table runspot_private.running_groups add column auto_start_on_accept boolean not null default false;

create function runspot_private.group_action_from_app(requested_group uuid,operation text,target_id uuid,client_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
  if operation='invite_and_start' then
    if requested_group is not null or target_id is null or target_id=auth.uid() then
      raise exception '초대 대상을 확인해 주세요.' using errcode='22023';
    end if;
    result:=runspot_private.group_action(null,'create',target_id,null);
    perform runspot_private.group_action(result,'invite',target_id,null);
    update runspot_private.running_groups set auto_start_on_accept=true where id=result;
    return result;
  end if;
  if operation in ('invite','start') and runspot_private.group_allowed(requested_group)
      and exists(select 1 from runspot_private.running_groups
        where id=requested_group and auto_start_on_accept) then
    raise exception '이 초대는 친구가 수락하면 자동으로 출발합니다.' using errcode='P0001';
  end if;
  result:=runspot_private.group_action(requested_group,operation,target_id,client_id);
  if operation='accept' then
    if exists(select 1 from runspot_private.running_groups
        where id=result and auto_start_on_accept and state='lobby'
          and (not runspot_private.is_active(host_id) or not runspot_private.email_verified(host_id))) then
      raise exception '초대한 친구의 계정 상태를 확인해 주세요.' using errcode='42501';
    end if;
    update runspot_private.running_groups
      set state='scheduled', starts_at=clock_timestamp()+interval '10 seconds',
          expires_at=clock_timestamp()+interval '24 hours'
      where id=result and auto_start_on_accept and state='lobby';
  elsif operation='reject' then
    update runspot_private.running_groups set state='cancelled'
      where id=result and auto_start_on_accept and state='lobby';
  end if;
  return result;
end;
$$;
revoke all on function runspot_private.group_action_from_app(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function runspot_private.group_action_from_app(uuid,text,uuid,uuid) to authenticated;
create or replace function public.group_action(requested_group uuid,operation text,target_id uuid default null,client_id uuid default null)
returns uuid language sql security invoker set search_path='' as $$
  select runspot_private.group_action_from_app(requested_group,operation,target_id,client_id);
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
        'my_status',mine.status,'auto_start_on_accept',g.auto_start_on_accept,'members',(
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
notify pgrst,'reload schema';
