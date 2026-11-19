-- 여러 명이 함께 쓰는 대화방(단톡)과 크루 대화방입니다. 1:1 친구 대화(friend_messages)는 그대로 둡니다.
-- - 단톡(group): 만든 사람이 친구나 같은 크루 사람을 골라 만들고, 참여자는 나갈 수 있습니다.
-- - 크루 대화방(crew): 크루마다 하나이며, 크루원이면 누구나 들어갑니다(크루를 나가면 함께 빠집니다).
create table runspot_private.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('group','crew')),
  crew_id uuid unique references runspot_private.crews(id) on delete cascade,
  name text check (name is null or char_length(name) between 1 and 30),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check ((kind='crew') = (crew_id is not null))
);
create table runspot_private.chat_room_members (
  room_id uuid not null references runspot_private.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(room_id,user_id)
);
create index chat_room_members_user on runspot_private.chat_room_members(user_id);
create table runspot_private.chat_room_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references runspot_private.chat_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000 and body ~ '[^[:space:]]'),
  request_id uuid not null,
  sent_at timestamptz not null default clock_timestamp(),
  unique(sender_id,request_id)
);
create index chat_room_messages_room on runspot_private.chat_room_messages(room_id,id desc);
create index chat_room_messages_sender on runspot_private.chat_room_messages(sender_id,sent_at desc);
create table runspot_private.chat_room_reads (
  room_id uuid not null references runspot_private.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_id bigint not null default 0,
  primary key(room_id,user_id)
);
alter table runspot_private.chat_rooms enable row level security;
alter table runspot_private.chat_room_members enable row level security;
alter table runspot_private.chat_room_messages enable row level security;
alter table runspot_private.chat_room_reads enable row level security;
revoke all on runspot_private.chat_rooms,runspot_private.chat_room_members,
  runspot_private.chat_room_messages,runspot_private.chat_room_reads from public,anon,authenticated;

-- 대화방 참여자입니다. 크루 대화방은 지금의 크루원이 참여자입니다.
create function runspot_private.chat_room_member_ids(target uuid)
returns setof uuid language sql stable security definer set search_path='' as $$
  select m.user_id from runspot_private.chat_room_members m
    join runspot_private.chat_rooms r on r.id=m.room_id where r.id=target and r.kind='group'
  union
  select c.user_id from runspot_private.crew_members c
    join runspot_private.chat_rooms r on r.crew_id=c.crew_id where r.id=target and r.kind='crew';
$$;
create function runspot_private.is_chat_room_member(target uuid,who uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from runspot_private.chat_room_member_ids(target) as member(uid) where member.uid=who);
$$;
create function runspot_private.chat_room_last_read(target uuid,who uuid)
returns bigint language sql stable security definer set search_path='' as $$
  select coalesce((select last_read_id from runspot_private.chat_room_reads where room_id=target and user_id=who),0);
$$;

-- 단톡에 넣을 수 있는 사람: 친구이거나 같은 크루에 있는 사람이며, 서로 차단하지 않았고 활동 중인 사람입니다.
create function runspot_private.can_add_to_room(target uuid,viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select target is not null and target<>viewer and runspot_private.is_active(target)
    and runspot_private.email_verified(target)
    and not exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=viewer and b.blocked_id=target) or (b.blocker_id=target and b.blocked_id=viewer))
    and (exists(select 1 from public.friendships f
          where f.user_low=least(viewer,target) and f.user_high=greatest(viewer,target) and f.status='accepted')
      or exists(select 1 from runspot_private.crew_members a join runspot_private.crew_members b on b.crew_id=a.crew_id
          where a.user_id=viewer and b.user_id=target));
$$;

create function runspot_private.require_room_member(target uuid)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if not runspot_private.can_interact() or target is null
     or not runspot_private.is_chat_room_member(target,viewer) then
    raise exception '대화방에 들어갈 수 없습니다.' using errcode='42501';
  end if;
  return viewer;
end;
$$;

-- 단톡을 만듭니다. 나 말고 1~49명을 고릅니다.
create function runspot_private.create_chat_room(member_ids uuid[],room_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer(); others uuid[]; created uuid; name_value text := nullif(btrim(room_name),'');
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 대화방을 만들 수 있습니다.' using errcode='42501';
  end if;
  select array_agg(distinct m) into others from unnest(coalesce(member_ids,'{}')) m where m<>viewer;
  if others is null or cardinality(others) not between 1 and 49 then
    raise exception '대화할 사람을 1~49명 골라 주세요.' using errcode='22023';
  end if;
  if name_value is not null and char_length(name_value) > 30 then
    raise exception '대화방 이름은 30자까지 쓸 수 있어요.' using errcode='22023';
  end if;
  if exists(select 1 from unnest(others) m where not runspot_private.can_add_to_room(m,viewer)) then
    raise exception '친구나 같은 크루 사람만 초대할 수 있어요.' using errcode='42501';
  end if;
  if (select count(*) from runspot_private.chat_rooms where created_by=viewer and created_at>now()-interval '1 hour') >= 20 then
    raise exception '대화방은 한 시간에 20개까지 만들 수 있어요.' using errcode='P0001';
  end if;
  insert into runspot_private.chat_rooms(kind,name,created_by) values('group',name_value,viewer) returning id into created;
  insert into runspot_private.chat_room_members(room_id,user_id)
    select created,viewer union select created,m from unnest(others) m;
  return created;
end;
$$;

-- 크루 대화방으로 들어갑니다. 처음 들어가는 사람이 있을 때 만듭니다.
create function runspot_private.crew_chat_room(requested_crew uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer(); found_id uuid;
begin
  if not exists(select 1 from runspot_private.crew_members where crew_id=requested_crew and user_id=viewer) then
    raise exception '크루원만 크루 대화방에 들어갈 수 있어요.' using errcode='42501';
  end if;
  insert into runspot_private.chat_rooms(kind,crew_id,created_by) values('crew',requested_crew,viewer)
  on conflict (crew_id) do nothing;
  select id into found_id from runspot_private.chat_rooms where crew_id=requested_crew;
  return found_id;
end;
$$;

-- 대화방 이름: 크루 대화방은 크루 이름, 단톡은 정한 이름이나 참여자 닉네임입니다.
create function runspot_private.chat_room_title(target uuid,viewer uuid)
returns text language sql stable security definer set search_path='' as $$
  select coalesce(
    (select c.name from runspot_private.chat_rooms r join runspot_private.crews c on c.id=r.crew_id where r.id=target),
    (select r.name from runspot_private.chat_rooms r where r.id=target),
    (select string_agg(coalesce(p.nickname,'알 수 없음'),', ' order by p.nickname)
      from runspot_private.chat_room_member_ids(target) as member(uid) left join public.profiles p on p.id=member.uid
      where member.uid<>viewer),
    '대화방');
$$;

create function runspot_private.my_chat_rooms()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(row order by (row->>'active_at') desc),'[]'::jsonb) from (
    select jsonb_build_object('room_id',r.id,'kind',r.kind,'crew_id',r.crew_id,
      'crew_icon',(select icon from runspot_private.crews where id=r.crew_id),
      'title',runspot_private.chat_room_title(r.id,viewer),
      'member_count',(select count(*) from runspot_private.chat_room_member_ids(r.id)),
      'id',m.id,'body',m.body,'sent_at',m.sent_at,
      'active_at',coalesce(m.sent_at,r.created_at),
      'unread',(select count(*) from runspot_private.chat_room_messages u where u.room_id=r.id
        and u.sender_id<>viewer and u.id>runspot_private.chat_room_last_read(r.id,viewer))) as row
    from runspot_private.chat_rooms r
    left join lateral (select id,body,sent_at from runspot_private.chat_room_messages
      where room_id=r.id order by id desc limit 1) m on true
    where runspot_private.is_chat_room_member(r.id,viewer)
      -- 크루 대화방은 메시지가 생긴 뒤부터 목록에 보입니다.
      and (r.kind='group' or m.id is not null)) x);
end;
$$;

-- 대화방 정보와 메시지(최신 50개)입니다. 메시지마다 아직 안 읽은 사람 수(unread)를 붙입니다.
create function runspot_private.chat_room_read(target uuid,before_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target);
begin
  return jsonb_build_object(
    'room',(select jsonb_build_object('room_id',r.id,'kind',r.kind,'crew_id',r.crew_id,
        'title',runspot_private.chat_room_title(r.id,viewer)) from runspot_private.chat_rooms r where r.id=target),
    'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',member.uid,'nickname',coalesce(p.nickname,'알 수 없음'))
        order by p.nickname),'[]'::jsonb)
      from runspot_private.chat_room_member_ids(target) as member(uid) left join public.profiles p on p.id=member.uid),
    'messages',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'sender_id',m.sender_id,
        'nickname',coalesce(p.nickname,'알 수 없음'),'body',m.body,'sent_at',m.sent_at,
        'unread',(select count(*) from runspot_private.chat_room_member_ids(target) as member(uid)
          where member.uid<>m.sender_id and runspot_private.chat_room_last_read(target,member.uid)<m.id))
        order by m.id desc),'[]'::jsonb)
      from (select * from runspot_private.chat_room_messages
        where room_id=target and (before_id is null or id<before_id)
          -- 차단한 사람의 메시지는 보이지 않게 합니다.
          and not exists(select 1 from runspot_private.blocks b
            where (b.blocker_id=viewer and b.blocked_id=sender_id) or (b.blocker_id=sender_id and b.blocked_id=viewer))
        order by id desc limit 50) m
      left join public.profiles p on p.id=m.sender_id));
end;
$$;

create function runspot_private.chat_room_send(target uuid,message_body text,request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target); cleaned text := btrim(message_body);
begin
  if request_id is null then raise exception '메시지를 다시 보내 주세요.' using errcode='22023'; end if;
  if cleaned is null or char_length(cleaned) not between 1 and 1000 or cleaned !~ '[^[:space:]]' then
    raise exception '메시지는 1~1000자로 입력해 주세요.' using errcode='22023';
  end if;
  if exists(select 1 from runspot_private.chat_room_messages m
      where m.sender_id=viewer and m.request_id=chat_room_send.request_id) then
    return;
  end if;
  if (select count(*) from runspot_private.chat_room_messages
      where sender_id=viewer and sent_at>clock_timestamp()-interval '1 minute') >= 30 then
    raise exception '잠시 후 메시지를 다시 보내 주세요.' using errcode='P0001';
  end if;
  insert into runspot_private.chat_room_messages(room_id,sender_id,body,request_id)
  values(target,viewer,cleaned,request_id);
end;
$$;

create function runspot_private.chat_room_mark_read(target uuid,last_id bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target); value bigint;
begin
  if last_id is null or last_id < 0 then raise exception '읽은 메시지를 확인해 주세요.' using errcode='22023'; end if;
  select coalesce(max(id),0) into value from runspot_private.chat_room_messages where room_id=target and id<=last_id;
  insert into runspot_private.chat_room_reads as r(room_id,user_id,last_read_id) values(target,viewer,value)
  on conflict on constraint chat_room_reads_pkey do update set last_read_id=greatest(r.last_read_id,excluded.last_read_id)
    where excluded.last_read_id>r.last_read_id;
  return runspot_private.chat_room_last_read(target,viewer);
end;
$$;

-- 단톡에서 나갑니다. 마지막 사람이 나가면 대화방을 지웁니다. 크루 대화방은 크루를 나가야 빠집니다.
create function runspot_private.leave_chat_room(target uuid)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_room_member(target);
begin
  if (select kind from runspot_private.chat_rooms where id=target)='crew' then
    raise exception '크루 대화방은 크루를 나가면 함께 나가져요.' using errcode='P0001';
  end if;
  delete from runspot_private.chat_room_members where room_id=target and user_id=viewer;
  delete from runspot_private.chat_room_reads where room_id=target and user_id=viewer;
  if not exists(select 1 from runspot_private.chat_room_members where room_id=target) then
    delete from runspot_private.chat_rooms where id=target;
  end if;
end;
$$;

create function runspot_private.chat_rooms_unread_total()
returns integer language sql stable security definer set search_path='' as $$
  select coalesce(sum((select count(*) from runspot_private.chat_room_messages u where u.room_id=r.id
      and u.sender_id<>auth.uid() and u.id>runspot_private.chat_room_last_read(r.id,auth.uid()))),0)::integer
  from runspot_private.chat_rooms r where runspot_private.is_chat_room_member(r.id,auth.uid());
$$;

-- 실시간: 대화방 메시지·읽음이 바뀌면 참여자 모두의 비공개 주제(chat:사용자ID)로 빈 신호를 보냅니다.
create function runspot_private.notify_chat_room()
returns trigger language plpgsql security definer set search_path='' as $$
declare member uuid;
begin
  for member in select runspot_private.chat_room_member_ids(new.room_id) loop
    perform realtime.send('{}'::jsonb,'changed','chat:'||member::text,true);
  end loop;
  return null;
end;
$$;
revoke all on function runspot_private.notify_chat_room() from public,anon,authenticated;
create trigger chat_room_messages_live after insert on runspot_private.chat_room_messages
for each row execute function runspot_private.notify_chat_room();
create trigger chat_room_reads_live after insert or update on runspot_private.chat_room_reads
for each row execute function runspot_private.notify_chat_room();

-- 휴대폰 알림: 단톡 새 메시지(room_message). 내용은 넣지 않고 대화방별로 묶습니다.
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
  check(kind in ('friend_request','group_invite','board_comment','friend_message','room_message'));
create function runspot_private.enqueue_room_message_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  select member,new.sender_id,'room_message',new.room_id,'room:'||new.id||':'||member
  from runspot_private.chat_room_member_ids(new.room_id) as m(member) where m.member<>new.sender_id
  on conflict(source_key) do nothing;
  return null;
end;
$$;
revoke all on function runspot_private.enqueue_room_message_push() from public,anon,authenticated;
create trigger chat_room_messages_push after insert on runspot_private.chat_room_messages
for each row execute function runspot_private.enqueue_room_message_push();

create or replace function runspot_private.push_allowed(j runspot_private.push_jobs)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.is_active(j.recipient_id) and runspot_private.is_active(j.actor_id)
 and not exists(select 1 from runspot_private.blocks where (blocker_id=j.actor_id and blocked_id=j.recipient_id) or (blocker_id=j.recipient_id and blocked_id=j.actor_id))
 and coalesce((select case j.kind when 'friend_request' then p.friend_request when 'group_invite' then p.group_invite
   when 'friend_message' then p.friend_message when 'room_message' then p.friend_message else p.board_comment end
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
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;

create function public.my_chat_rooms() returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.my_chat_rooms(); $$;
create function public.create_chat_room(member_ids uuid[],room_name text default null) returns uuid language sql
security invoker set search_path='' as $$ select runspot_private.create_chat_room(member_ids,room_name); $$;
create function public.crew_chat_room(requested_crew uuid) returns uuid language sql security invoker set search_path=''
as $$ select runspot_private.crew_chat_room(requested_crew); $$;
create function public.chat_room_read(target uuid,before_id bigint default null) returns jsonb language sql stable
security invoker set search_path='' as $$ select runspot_private.chat_room_read(target,before_id); $$;
create function public.chat_room_send(target uuid,message_body text,request_id uuid) returns void language sql
security invoker set search_path='' as $$ select runspot_private.chat_room_send(target,message_body,request_id); $$;
create function public.chat_room_mark_read(target uuid,last_id bigint) returns bigint language sql
security invoker set search_path='' as $$ select runspot_private.chat_room_mark_read(target,last_id); $$;
create function public.leave_chat_room(target uuid) returns void language sql security invoker set search_path=''
as $$ select runspot_private.leave_chat_room(target); $$;
create function public.chat_rooms_unread_total() returns integer language sql stable security invoker set search_path=''
as $$ select runspot_private.chat_rooms_unread_total(); $$;

revoke all on function runspot_private.chat_room_member_ids(uuid),runspot_private.is_chat_room_member(uuid,uuid),
  runspot_private.chat_room_last_read(uuid,uuid),runspot_private.can_add_to_room(uuid,uuid),
  runspot_private.require_room_member(uuid),runspot_private.chat_room_title(uuid,uuid),
  runspot_private.create_chat_room(uuid[],text),runspot_private.crew_chat_room(uuid),runspot_private.my_chat_rooms(),
  runspot_private.chat_room_read(uuid,bigint),runspot_private.chat_room_send(uuid,text,uuid),
  runspot_private.chat_room_mark_read(uuid,bigint),runspot_private.leave_chat_room(uuid),
  runspot_private.chat_rooms_unread_total(),
  public.my_chat_rooms(),public.create_chat_room(uuid[],text),public.crew_chat_room(uuid),
  public.chat_room_read(uuid,bigint),public.chat_room_send(uuid,text,uuid),public.chat_room_mark_read(uuid,bigint),
  public.leave_chat_room(uuid),public.chat_rooms_unread_total() from public,anon,authenticated;
grant execute on function
  runspot_private.create_chat_room(uuid[],text),runspot_private.crew_chat_room(uuid),runspot_private.my_chat_rooms(),
  runspot_private.chat_room_read(uuid,bigint),runspot_private.chat_room_send(uuid,text,uuid),
  runspot_private.chat_room_mark_read(uuid,bigint),runspot_private.leave_chat_room(uuid),
  runspot_private.chat_rooms_unread_total(),
  public.my_chat_rooms(),public.create_chat_room(uuid[],text),public.crew_chat_room(uuid),
  public.chat_room_read(uuid,bigint),public.chat_room_send(uuid,text,uuid),public.chat_room_mark_read(uuid,bigint),
  public.leave_chat_room(uuid),public.chat_rooms_unread_total() to authenticated;
notify pgrst,'reload schema';
