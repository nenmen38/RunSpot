-- 첨부 데이터는 메시지와 같은 트랜잭션에 저장하고, 사진은 별도 권한 검사 후 조회합니다.
alter table runspot_private.friend_messages
  add column kind text not null default 'text' check (kind in ('text','photo','run','deleted')),
  add column reply_id bigint references runspot_private.friend_messages(id) on delete set null,
  add column photo bytea check (octet_length(photo) between 4 and 1048576),
  add column run_summary jsonb,
  add constraint friend_message_payload check (
    (kind='photo')=(photo is not null) and (kind='run')=(run_summary is not null)
  );

create index friend_messages_reply on runspot_private.friend_messages(reply_id) where reply_id is not null;

create function runspot_private.friend_chat_send_content(
  peer_id uuid, message_body text, request_id uuid, reply_to bigint, jpeg text, run_id uuid
) returns void language plpgsql security definer set search_path='' as $$
declare
  viewer uuid := auth.uid();
  cleaned text := btrim(message_body);
  message_kind text := 'text';
  image_bytes bytea;
  summary jsonb;
  existing runspot_private.friend_messages%rowtype;
begin
  if viewer is null or peer_id is null or viewer=peer_id or request_id is null then
    raise exception '대화 상대를 확인해 주세요.' using errcode='42501';
  end if;
  if num_nonnulls(message_body,jpeg,run_id)<>1 then
    raise exception '한 종류의 메시지를 선택해 주세요.' using errcode='22023';
  end if;
  -- 친구 및 차단 상태 변경과 같은 순서로 잠급니다.
  perform 1 from auth.users where id in (viewer,peer_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (viewer,peer_id) order by user_id for share;
  perform 1 from public.profiles where id in (viewer,peer_id) order by id for update;
  if not runspot_private.can_chat_with(peer_id) then
    raise exception '친구에게만 메시지를 보낼 수 있습니다.' using errcode='42501';
  end if;
  if reply_to is not null and not exists(
    select 1 from runspot_private.friend_messages m where m.id=reply_to
      and m.user_low=least(viewer,peer_id) and m.user_high=greatest(viewer,peer_id)
  ) then
    raise exception '이 대화의 메시지에만 답장할 수 있습니다.' using errcode='22023';
  end if;
  if jpeg is not null then
    if octet_length(jpeg)>1398104 then
      raise exception '사진은 1MB 이하여야 합니다.' using errcode='22023';
    end if;
    image_bytes := decode(jpeg,'base64');
    if octet_length(image_bytes) not between 4 and 1048576
      or substring(image_bytes from 1 for 3)<>decode('ffd8ff','hex')
      or substring(image_bytes from octet_length(image_bytes)-1)<>decode('ffd9','hex') then
      raise exception 'JPEG 사진을 선택해 주세요.' using errcode='22023';
    end if;
    message_kind := 'photo';
    cleaned := '사진';
  elsif run_id is not null then
    message_kind := 'run';
    cleaned := '달리기 기록';
  end if;

  select * into existing from runspot_private.friend_messages m
    where m.sender_id=viewer and m.request_id=friend_chat_send_content.request_id;
  if found then
    if existing.recipient_id=peer_id and (
      existing.kind='deleted' or (
        existing.kind=message_kind and existing.body=cleaned
        and existing.reply_id is not distinct from reply_to
        and existing.photo is not distinct from image_bytes
        and existing.run_summary->>'source_id' is not distinct from run_id::text
      )
    ) then return; end if;
    raise exception '메시지 요청이 이미 사용되었습니다.' using errcode='22023';
  end if;
  if cleaned is null or char_length(cleaned) not between 1 and 1000 or cleaned !~ '[^[:space:]]' then
    raise exception '메시지는 1~1000자로 입력해 주세요.' using errcode='22023';
  end if;
  if run_id is not null then
    -- 소유한 공개 가능 기록의 거리와 시간만 복사합니다. 위치와 경로는 조회하지 않습니다.
    select jsonb_build_object('source_id',r.id,'distance_m',r.distance_m,'duration_sec',r.duration_sec)
    into summary from public.runs r
    where r.id=run_id and r.user_id=viewer and not r.hidden;
    if not found then
      raise exception '공유할 수 없는 달리기 기록입니다.' using errcode='42501';
    end if;
  end if;
  if (select count(*) from runspot_private.friend_messages m
      where m.sender_id=viewer and m.sent_at>clock_timestamp()-interval '1 minute')>=30 then
    raise exception '잠시 후 메시지를 다시 보내 주세요.' using errcode='P0001';
  end if;
  if message_kind='photo' and (select count(*) from runspot_private.friend_messages m
      where m.sender_id=viewer and m.kind='photo' and m.sent_at>clock_timestamp()-interval '1 minute')>=5 then
    raise exception '잠시 후 사진을 다시 보내 주세요.' using errcode='P0001';
  end if;
  insert into runspot_private.friend_messages(sender_id,recipient_id,body,request_id,kind,reply_id,photo,run_summary)
  values(viewer,peer_id,cleaned,request_id,message_kind,reply_to,image_bytes,summary);
end;
$$;

create or replace function runspot_private.friend_chat_send(peer_id uuid,message_body text,request_id uuid)
returns void language sql security invoker set search_path='' as $$
  select runspot_private.friend_chat_send_content(peer_id,message_body,request_id,null,null,null);
$$;

create function runspot_private.friend_chat_photo(peer_id uuid,message_id bigint)
returns text language sql stable security definer set search_path='' as $$
  select encode(m.photo,'base64') from runspot_private.friend_messages m
   where m.id=message_id and m.kind='photo' and runspot_private.can_chat_with(peer_id)
     and m.user_low=least(auth.uid(),peer_id) and m.user_high=greatest(auth.uid(),peer_id);
$$;

create function runspot_private.friend_chat_delete(peer_id uuid,message_id bigint)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not runspot_private.can_chat_with(peer_id) then
    raise exception '대화에 접근할 수 없습니다.' using errcode='42501';
  end if;
  update runspot_private.friend_messages m
    set kind='deleted',body='삭제된 메시지입니다.',photo=null,run_summary=null,reply_id=null
    where m.id=message_id and m.sender_id=auth.uid() and m.recipient_id=peer_id and m.kind<>'deleted';
  if not found and not exists(select 1 from runspot_private.friend_messages m
    where m.id=message_id and m.sender_id=auth.uid() and m.recipient_id=peer_id and m.kind='deleted') then
    raise exception '내가 보낸 메시지만 삭제할 수 있습니다.' using errcode='42501';
  end if;
end;
$$;

create trigger friend_messages_delete_live after update of kind on runspot_private.friend_messages
for each row when (new.kind='deleted' and old.kind<>'deleted') execute function runspot_private.notify_friend_chat();

create function public.friend_chat_send_content(
  peer_id uuid, message_body text, request_id uuid, reply_to bigint, jpeg text, run_id uuid
) returns void language sql security invoker set search_path='' as $$
  select runspot_private.friend_chat_send_content(peer_id,message_body,request_id,reply_to,jpeg,run_id);
$$;
create function public.friend_chat_photo(peer_id uuid,message_id bigint)
returns text language sql stable security invoker set search_path='' as $$
  select runspot_private.friend_chat_photo(peer_id,message_id);
$$;
create function public.friend_chat_delete(peer_id uuid,message_id bigint)
returns void language sql security invoker set search_path='' as $$
  select runspot_private.friend_chat_delete(peer_id,message_id);
$$;

revoke all on function
  runspot_private.friend_chat_send_content(uuid,text,uuid,bigint,text,uuid),
  public.friend_chat_send_content(uuid,text,uuid,bigint,text,uuid),
  runspot_private.friend_chat_photo(uuid,bigint),public.friend_chat_photo(uuid,bigint),
  runspot_private.friend_chat_delete(uuid,bigint),public.friend_chat_delete(uuid,bigint)
from public,anon,authenticated;
grant execute on function
  runspot_private.friend_chat_send_content(uuid,text,uuid,bigint,text,uuid),
  public.friend_chat_send_content(uuid,text,uuid,bigint,text,uuid),
  runspot_private.friend_chat_photo(uuid,bigint),public.friend_chat_photo(uuid,bigint),
  runspot_private.friend_chat_delete(uuid,bigint),public.friend_chat_delete(uuid,bigint)
to authenticated;

create or replace function runspot_private.friend_chat_read(peer_id uuid,before_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); peer_read bigint;
begin
  if not runspot_private.can_interact() or
      (peer_id is not null and not runspot_private.can_chat_with(peer_id)) then
    raise exception '대화에 접근할 수 없습니다.' using errcode='42501';
  end if;
  if peer_id is not null then
    -- 내가 보낸 메시지에 상대가 읽었는지(read)를 붙입니다.
    peer_read := runspot_private.friend_chat_last_read(peer_id,viewer);
    return (select coalesce(jsonb_agg(to_jsonb(m) order by m.id desc),'[]'::jsonb)
      from (select msg.id,msg.sender_id,msg.body,msg.sent_at,msg.kind,
          msg.run_summary-'source_id' as run_summary, msg.reply_id, left(original.body,160) as reply_preview,
          (msg.kind='deleted' or msg.sender_id<>viewer or msg.id<=peer_read) as read
        from runspot_private.friend_messages msg
        left join runspot_private.friend_messages original on original.id=msg.reply_id
        where msg.user_low=least(viewer,peer_id) and msg.user_high=greatest(viewer,peer_id)
          and (before_id is null or msg.id<before_id)
        order by msg.id desc limit 50) m);
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(room) order by room.id desc),'[]'::jsonb)
    from (select p.id as peer_id,p.nickname,m.id,m.body,m.sent_at,
        (select count(*) from runspot_private.friend_messages u
          where u.sender_id=p.id and u.recipient_id=viewer
            and u.kind<>'deleted' and u.id>runspot_private.friend_chat_last_read(viewer,p.id)) as unread
      from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      cross join lateral (select id,body,sent_at from runspot_private.friend_messages
        where user_low=f.user_low and user_high=f.user_high order by id desc limit 1) m
      where (f.user_low=viewer or f.user_high=viewer) and f.status='accepted'
        and runspot_private.can_chat_with(p.id)
      order by m.id desc) room);
end;
$$;


create or replace function runspot_private.friend_chat_unread_total()
returns integer language sql stable security definer set search_path='' as $$
  select coalesce(sum((select count(*) from runspot_private.friend_messages m
      where m.sender_id=p.peer and m.recipient_id=auth.uid()
        and m.kind<>'deleted' and m.id>runspot_private.friend_chat_last_read(auth.uid(),p.peer))),0)::integer
  from (select distinct sender_id as peer from runspot_private.friend_messages where recipient_id=auth.uid()) p
  where runspot_private.can_chat_with(p.peer);
$$;

create or replace function runspot_private.push_allowed(j runspot_private.push_jobs)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.is_active(j.recipient_id) and runspot_private.is_active(j.actor_id)
 and not exists(select 1 from runspot_private.blocks where (blocker_id=j.actor_id and blocked_id=j.recipient_id) or (blocker_id=j.recipient_id and blocked_id=j.actor_id))
 and coalesce((select case j.kind when 'friend_request' then p.friend_request when 'group_invite' then p.group_invite
   when 'friend_message' then p.friend_message else p.board_comment end
  from runspot_private.push_preferences p where p.user_id=j.recipient_id),true)
 and case j.kind
 when 'friend_request' then exists(select 1 from public.friendships f where f.relationship_id=j.target_id and f.status='pending' and f.requested_by=j.actor_id)
 when 'group_invite' then exists(select 1 from runspot_private.running_groups g join runspot_private.running_group_members m on m.group_id=g.id
  where g.id=j.target_id and g.state='lobby' and g.expires_at>now() and m.user_id=j.recipient_id and m.status='invited')
 when 'friend_message' then exists(select 1 from public.friendships f
   where f.user_low=least(j.recipient_id,j.actor_id) and f.user_high=greatest(j.recipient_id,j.actor_id) and f.status='accepted')
  and exists(select 1 from runspot_private.friend_messages m where m.kind<>'deleted' and 'chat:'||m.id=j.source_key
   and m.id>runspot_private.friend_chat_last_read(j.recipient_id,j.actor_id))
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;

notify pgrst,'reload schema';
