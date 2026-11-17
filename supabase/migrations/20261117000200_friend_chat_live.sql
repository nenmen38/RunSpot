-- 친구 대화 마무리: 안 읽은 메시지 총 개수, 새 메시지 휴대폰 알림, 실시간 반영입니다.

-- 1) 소셜 탭 배지에 쓰는 안 읽은 메시지 총 개수입니다. 친구·차단 상태가 바뀌면 그 대화는 세지 않습니다.
create function runspot_private.friend_chat_unread_total()
returns integer language sql stable security definer set search_path='' as $$
  select coalesce(sum((select count(*) from runspot_private.friend_messages m
      where m.sender_id=p.peer and m.recipient_id=auth.uid()
        and m.id>runspot_private.friend_chat_last_read(auth.uid(),p.peer))),0)::integer
  from (select distinct sender_id as peer from runspot_private.friend_messages where recipient_id=auth.uid()) p
  where runspot_private.can_chat_with(p.peer);
$$;
create function public.friend_chat_unread_total()
returns integer language sql stable security invoker set search_path='' as $$
  select runspot_private.friend_chat_unread_total();
$$;
revoke all on function runspot_private.friend_chat_unread_total(),public.friend_chat_unread_total() from public,anon,authenticated;
grant execute on function runspot_private.friend_chat_unread_total(),public.friend_chat_unread_total() to authenticated;

-- 2) 실시간 반영: 메시지·읽음이 바뀌면 당사자 두 사람의 비공개 주제(chat:사용자ID)로 빈 신호만 보냅니다.
--    내용은 보내지 않고, 앱이 신호를 받으면 권한을 다시 검사하는 조회로 새로 불러옵니다.
create function runspot_private.notify_friend_chat()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='friend_messages' then
    perform realtime.send('{}'::jsonb,'changed','chat:'||new.sender_id::text,true);
    perform realtime.send('{}'::jsonb,'changed','chat:'||new.recipient_id::text,true);
  else
    perform realtime.send('{}'::jsonb,'changed','chat:'||new.user_id::text,true);
    perform realtime.send('{}'::jsonb,'changed','chat:'||new.peer_id::text,true);
  end if;
  return null;
end;
$$;
revoke all on function runspot_private.notify_friend_chat() from public,anon,authenticated;
create trigger friend_messages_live after insert on runspot_private.friend_messages
for each row execute function runspot_private.notify_friend_chat();
create trigger friend_chat_reads_live after insert or update on runspot_private.friend_chat_reads
for each row execute function runspot_private.notify_friend_chat();
-- 자기 주제의 신호만 받을 수 있고 보낼 수는 없습니다.
create policy friend_chat_broadcast_read on realtime.messages for select to authenticated
using (realtime.topic()='chat:'||auth.uid()::text and extension='broadcast' and runspot_private.can_interact());

-- 3) 새 메시지 휴대폰 알림입니다. 알림 내용에는 메시지 본문을 넣지 않습니다.
alter table runspot_private.push_preferences add column friend_message boolean not null default true;
do $$
declare item record;
begin
  for item in select conname from pg_constraint
    where conrelid='runspot_private.push_jobs'::regclass and contype='c' and pg_get_constraintdef(oid) like '%kind%'
  loop
    execute format('alter table runspot_private.push_jobs drop constraint %I',item.conname);
  end loop;
end;
$$;
alter table runspot_private.push_jobs add constraint push_jobs_kind_check
  check(kind in ('friend_request','group_invite','board_comment','friend_message'));

create function runspot_private.enqueue_friend_message_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- 같은 친구가 연달아 보내도 대상(target_id)은 보낸 친구라 휴대폰에서 알림 하나로 묶입니다.
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  values(new.recipient_id,new.sender_id,'friend_message',new.sender_id,'chat:'||new.id)
  on conflict(source_key) do nothing;
  return null;
end;
$$;
revoke all on function runspot_private.enqueue_friend_message_push() from public,anon,authenticated;
create trigger friend_messages_push after insert on runspot_private.friend_messages
for each row execute function runspot_private.enqueue_friend_message_push();

-- 발송 직전에 다시 검사합니다. 이미 읽은 메시지는 알리지 않습니다.
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
  and exists(select 1 from runspot_private.friend_messages m where 'chat:'||m.id=j.source_key
   and m.id>runspot_private.friend_chat_last_read(j.recipient_id,j.actor_id))
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;

-- 알림 설정에 '친구 메시지'를 더합니다. 이전 앱은 이 값 없이 그대로 호출할 수 있습니다.
drop function public.my_push_preferences(boolean,boolean,boolean);
drop function runspot_private.my_push_preferences(boolean,boolean,boolean);
create function runspot_private.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); result jsonb;
begin
 if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 insert into runspot_private.push_preferences as p(user_id,friend_request,group_invite,board_comment,friend_message)
 values(viewer,coalesce(friend_request,true),coalesce(group_invite,true),coalesce(board_comment,true),coalesce(friend_message,true))
 on conflict(user_id) do update set friend_request=coalesce(my_push_preferences.friend_request,p.friend_request),
 group_invite=coalesce(my_push_preferences.group_invite,p.group_invite),board_comment=coalesce(my_push_preferences.board_comment,p.board_comment),
 friend_message=coalesce(my_push_preferences.friend_message,p.friend_message)
 returning to_jsonb(p)-'user_id' into result;
 return result;
end;
$$;
create function public.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null)
returns jsonb language sql security invoker set search_path='' as $$
  select runspot_private.my_push_preferences(friend_request,group_invite,board_comment,friend_message);
$$;
revoke all on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
