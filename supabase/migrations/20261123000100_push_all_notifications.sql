-- 앱 알림창의 모든 알림(좋아요·크루 초대 포함)을 휴대폰 알림으로도 보냅니다.
-- 알림 문구에 보낸 사람 이름과 내용(메시지·댓글)을 넣고, 항목별로 켜고 끌 수 있게 합니다.

-- 1) 수신 설정 항목을 나눕니다. 단톡은 지금까지 친구 메시지 설정을 따랐으므로 그 값을 이어받습니다.
alter table runspot_private.push_preferences
  add column room_message boolean not null default true,
  add column board_like boolean not null default true,
  add column crew_invite boolean not null default true,
  -- 끄면 잠금 화면에 이름·내용 없이 '새 메시지가 도착했어요' 같은 문구만 보여줍니다.
  add column show_preview boolean not null default true;
update runspot_private.push_preferences set room_message=friend_message;

-- 2) 새 알림 종류를 받을 수 있게 합니다.
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
  check(kind in ('friend_request','group_invite','board_comment','friend_message','room_message','board_like','crew_invite'));

-- 3) 알림창에 쌓이는 좋아요·크루 초대도 휴대폰 알림 작업을 만듭니다. (함께 달리기 초대는 참여자 표에서 이미 만듭니다.)
create or replace function runspot_private.enqueue_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='friendships' then
  if new.status<>'pending' then return null; end if;
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  values(case when new.requested_by=new.user_low then new.user_high else new.user_low end,new.requested_by,'friend_request',new.relationship_id,'friend:'||new.relationship_id)
  on conflict(source_key) do nothing;
 elsif tg_table_name='running_group_members' then
  if new.status<>'invited' then return null; end if;
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  select new.user_id,g.host_id,'group_invite',g.id,'group:'||g.id||':'||new.user_id from runspot_private.running_groups g where g.id=new.group_id
  on conflict(source_key) do nothing;
 elsif tg_table_name='notifications' then
  if new.kind in ('comment','reply') then
   insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
   values(new.recipient_id,new.actor_id,'board_comment',new.post_id,'comment:'||new.id) on conflict(source_key) do nothing;
  elsif new.kind='like' and new.post_id is not null then
   insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
   values(new.recipient_id,new.actor_id,'board_like',new.post_id,'like:'||new.id) on conflict(source_key) do nothing;
  elsif new.kind='crew_invite' and new.crew_id is not null then
   insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
   values(new.recipient_id,new.actor_id,'crew_invite',new.crew_id,'crew:'||new.id) on conflict(source_key) do nothing;
  end if;
 end if;
 return null;
end;
$$;
revoke all on function runspot_private.enqueue_push() from public,anon,authenticated;

-- 4) 발송 직전 검사: 항목별 수신 설정과 새 종류(좋아요 취소·초대 처리됨)를 확인합니다.
create or replace function runspot_private.push_allowed(j runspot_private.push_jobs)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.is_active(j.recipient_id) and runspot_private.is_active(j.actor_id)
 and not exists(select 1 from runspot_private.blocks where (blocker_id=j.actor_id and blocked_id=j.recipient_id) or (blocker_id=j.recipient_id and blocked_id=j.actor_id))
 and coalesce((select case j.kind when 'friend_request' then p.friend_request when 'group_invite' then p.group_invite
   when 'friend_message' then p.friend_message when 'room_message' then p.room_message
   when 'board_like' then p.board_like when 'crew_invite' then p.crew_invite else p.board_comment end
  from runspot_private.push_preferences p where p.user_id=j.recipient_id),true)
 and case j.kind
 when 'friend_request' then exists(select 1 from public.friendships f where f.relationship_id=j.target_id and f.status='pending' and f.requested_by=j.actor_id)
 when 'group_invite' then exists(select 1 from runspot_private.running_groups g join runspot_private.running_group_members m on m.group_id=g.id
  where g.id=j.target_id and g.state='lobby' and g.expires_at>now() and m.user_id=j.recipient_id and m.status='invited')
 when 'friend_message' then exists(select 1 from public.friendships f
   where f.user_low=least(j.recipient_id,j.actor_id) and f.user_high=greatest(j.recipient_id,j.actor_id) and f.status='accepted')
  and exists(select 1 from runspot_private.friend_messages m where m.kind<>'deleted' and 'chat:'||m.id=j.source_key
   and m.id>runspot_private.friend_chat_last_read(j.recipient_id,j.actor_id))
 when 'room_message' then runspot_private.is_chat_room_member(j.target_id,j.recipient_id)
  and exists(select 1 from runspot_private.chat_room_messages m where m.room_id=j.target_id
   and j.source_key='room:'||m.id||':'||j.recipient_id
   and m.id>runspot_private.chat_room_last_read(j.target_id,j.recipient_id))
 when 'board_like' then exists(select 1 from runspot_private.notifications n where 'like:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id))
 when 'crew_invite' then exists(select 1 from runspot_private.notifications n
   join runspot_private.crew_invites i on i.crew_id=n.crew_id and i.user_id=j.recipient_id and i.status='invited'
   where 'crew:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id))
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;
revoke all on function runspot_private.push_allowed(runspot_private.push_jobs) from public,anon,authenticated;

-- 5) 휴대폰에 보여줄 제목과 내용입니다. 보낸 사람 이름과 메시지·댓글 내용을 넣습니다.
--    수신자가 '내용 표시'를 끄면 이름·내용 없이 종류만 알립니다.
create function runspot_private.push_text(j runspot_private.push_jobs)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 who text := coalesce((select nullif(p.nickname,'') from public.profiles p where p.id=j.actor_id),'러너');
 preview boolean := coalesce((select p.show_preview from runspot_private.push_preferences p where p.user_id=j.recipient_id),true);
 content text;
 room text;
 note text;
begin
 if not preview then
  return jsonb_build_object('title','뜀터','body',case j.kind
   when 'friend_request' then '새 친구 요청이 도착했어요.'
   when 'group_invite' then '함께 달리기 초대가 도착했어요.'
   when 'crew_invite' then '크루 초대가 도착했어요.'
   when 'board_like' then '내 글에 좋아요가 달렸어요.'
   when 'friend_message' then '새 메시지가 도착했어요.'
   when 'room_message' then '단체 대화방에 새 메시지가 도착했어요.'
   else '내 글이나 댓글에 새 댓글이 달렸어요.' end);
 end if;
 case j.kind
 when 'friend_message' then
  select case m.kind when 'photo' then '사진을 보냈어요.' when 'run' then '러닝 기록을 공유했어요.' else m.body end
   into content from runspot_private.friend_messages m where 'chat:'||m.id=j.source_key;
  return jsonb_build_object('title',who,'body',left(coalesce(content,'새 메시지가 도착했어요.'),120));
 when 'room_message' then
  select case m.kind when 'photo' then '사진을 보냈어요.' else m.body end
   into content from runspot_private.chat_room_messages m where m.room_id=j.target_id and j.source_key='room:'||m.id||':'||j.recipient_id;
  room := runspot_private.chat_room_title(j.target_id,j.recipient_id);
  return jsonb_build_object('title',left(room,40),'body',left(who||': '||coalesce(content,'새 메시지'),120));
 when 'board_comment' then
  select c.body,n.kind into content,note from runspot_private.notifications n
   join runspot_private.board_comments c on c.id=n.comment_id where 'comment:'||n.id=j.source_key;
  return jsonb_build_object('title',case note when 'reply' then '새 답글' else '새 댓글' end,
   'body',left(who||': '||coalesce(content,''),120));
 when 'board_like' then
  select b.title into content from runspot_private.board_posts b where b.id=j.target_id;
  return jsonb_build_object('title','좋아요','body',left(who||'님이 내 글을 좋아해요: '||coalesce(content,''),120));
 when 'crew_invite' then
  select c.name into content from runspot_private.crews c where c.id=j.target_id;
  return jsonb_build_object('title','크루 초대','body',left(who||'님이 '||coalesce(content,'크루')||' 크루에 초대했어요.',120));
 when 'group_invite' then
  return jsonb_build_object('title','함께 달리기 초대','body',who||'님이 함께 달리기에 초대했어요.');
 else
  return jsonb_build_object('title','친구 요청','body',who||'님이 친구 요청을 보냈어요.');
 end case;
end;
$$;
revoke all on function runspot_private.push_text(runspot_private.push_jobs) from public,anon,authenticated;

-- 6) 발송 목록에 제목·내용을 함께 담아 서버 함수가 그대로 보냅니다.
create or replace function runspot_private.claim_push_deliveries()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 delete from runspot_private.push_jobs where created_at<now()-interval '1 day';
 delete from runspot_private.push_devices where refreshed_at<now()-interval '30 days';
 insert into runspot_private.push_deliveries(job_id,device_id)
 select j.id,d.id from runspot_private.push_jobs j join runspot_private.push_devices d on d.user_id=j.recipient_id
 where j.created_at>now()-interval '15 minutes' and d.registered_at<=j.created_at and runspot_private.push_allowed(j)
 on conflict do nothing;
 with candidates as (
  select q.job_id,q.device_id from runspot_private.push_deliveries q
  join runspot_private.push_jobs j on j.id=q.job_id join runspot_private.push_devices d on d.id=q.device_id
  where not q.done and q.attempts<5 and q.available_at<=now() and j.created_at>now()-interval '15 minutes'
   and d.user_id=j.recipient_id and runspot_private.push_allowed(j)
  order by q.available_at limit 20 for update of q skip locked
 ), claimed as (
  update runspot_private.push_deliveries q set attempts=q.attempts+1,lease=gen_random_uuid(),available_at=now()+interval '2 minutes'
  from candidates c where q.job_id=c.job_id and q.device_id=c.device_id returning q.*
 ) select coalesce(jsonb_agg(jsonb_build_object('job_id',q.job_id,'device_id',q.device_id,'lease',q.lease,'token',d.token,
  'recipient_id',j.recipient_id,'kind',j.kind,'target_id',j.target_id) || runspot_private.push_text(j)),'[]') into result
 from claimed q join runspot_private.push_jobs j on j.id=q.job_id join runspot_private.push_devices d on d.id=q.device_id;
 return result;
end;
$$;

-- 7) 설정 화면용: 모든 항목을 한 번에 읽고, 바꾼 항목만 저장합니다.
drop function public.my_push_preferences(boolean,boolean,boolean,boolean);
drop function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean);
create function runspot_private.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null,room_message boolean default null,
  board_like boolean default null,crew_invite boolean default null,show_preview boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); result jsonb;
begin
 if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 insert into runspot_private.push_preferences as p(user_id) values(viewer) on conflict(user_id) do nothing;
 update runspot_private.push_preferences p set
  friend_request=coalesce(my_push_preferences.friend_request,p.friend_request),
  group_invite=coalesce(my_push_preferences.group_invite,p.group_invite),
  board_comment=coalesce(my_push_preferences.board_comment,p.board_comment),
  friend_message=coalesce(my_push_preferences.friend_message,p.friend_message),
  room_message=coalesce(my_push_preferences.room_message,p.room_message),
  board_like=coalesce(my_push_preferences.board_like,p.board_like),
  crew_invite=coalesce(my_push_preferences.crew_invite,p.crew_invite),
  show_preview=coalesce(my_push_preferences.show_preview,p.show_preview)
 where p.user_id=viewer
 returning to_jsonb(p)-'user_id' into result;
 return result;
end;
$$;
create function public.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null,room_message boolean default null,
  board_like boolean default null,crew_invite boolean default null,show_preview boolean default null)
returns jsonb language sql security invoker set search_path='' as $$
  select runspot_private.my_push_preferences(friend_request,group_invite,board_comment,friend_message,
   room_message,board_like,crew_invite,show_preview);
$$;
revoke all on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
