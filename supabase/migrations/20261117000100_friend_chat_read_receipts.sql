-- 친구 대화의 읽음 표시입니다. 대화 상대별로 내가 어디까지 읽었는지(last_read_id)만 저장합니다.
-- 내 메시지는 상대가 읽기 전까지 '1'을 보여주고, 대화 목록에는 안 읽은 메시지 수를 보여줍니다.
create table runspot_private.friend_chat_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  peer_id uuid not null references auth.users(id) on delete cascade,
  last_read_id bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(user_id,peer_id),
  check (user_id<>peer_id)
);
alter table runspot_private.friend_chat_reads enable row level security;
revoke all on runspot_private.friend_chat_reads from public,anon,authenticated;

-- 이미 주고받은 메시지는 읽은 것으로 시작해 기존 대화에 '1'이 한꺼번에 붙지 않게 합니다.
insert into runspot_private.friend_chat_reads(user_id,peer_id,last_read_id)
select recipient_id,sender_id,max(id) from runspot_private.friend_messages group by recipient_id,sender_id
on conflict do nothing;

create function runspot_private.friend_chat_last_read(reader uuid,writer uuid)
returns bigint language sql stable security definer set search_path='' as $$
  select coalesce((select last_read_id from runspot_private.friend_chat_reads where user_id=reader and peer_id=writer),0);
$$;
revoke all on function runspot_private.friend_chat_last_read(uuid,uuid) from public,anon,authenticated;

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
      from (select id,sender_id,body,sent_at,(sender_id<>viewer or id<=peer_read) as read
        from runspot_private.friend_messages
        where user_low=least(viewer,peer_id) and user_high=greatest(viewer,peer_id)
          and (before_id is null or id<before_id)
        order by id desc limit 50) m);
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(room) order by room.id desc),'[]'::jsonb)
    from (select p.id as peer_id,p.nickname,m.id,m.body,m.sent_at,
        (select count(*) from runspot_private.friend_messages u
          where u.sender_id=p.id and u.recipient_id=viewer
            and u.id>runspot_private.friend_chat_last_read(viewer,p.id)) as unread
      from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      cross join lateral (select id,body,sent_at from runspot_private.friend_messages
        where user_low=f.user_low and user_high=f.user_high order by id desc limit 1) m
      where (f.user_low=viewer or f.user_high=viewer) and f.status='accepted'
        and runspot_private.can_chat_with(p.id)
      order by m.id desc) room);
end;
$$;

-- 대화방에서 본 메시지까지 읽음으로 표시합니다. 뒤로 되돌리지 않고, 실제로 받은 메시지 범위를 넘지 않습니다.
create function runspot_private.friend_chat_mark_read(peer_id uuid,last_id bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); target bigint;
begin
  if not runspot_private.can_chat_with(peer_id) then
    raise exception '대화에 접근할 수 없습니다.' using errcode='42501';
  end if;
  if last_id is null or last_id<0 then
    raise exception '읽은 메시지를 확인해 주세요.' using errcode='22023';
  end if;
  select coalesce(max(id),0) into target from runspot_private.friend_messages
    where sender_id=friend_chat_mark_read.peer_id and recipient_id=viewer and id<=last_id;
  insert into runspot_private.friend_chat_reads(user_id,peer_id,last_read_id) values(viewer,friend_chat_mark_read.peer_id,target)
  on conflict on constraint friend_chat_reads_pkey do update
    set last_read_id=greatest(runspot_private.friend_chat_reads.last_read_id,excluded.last_read_id),updated_at=now()
    where excluded.last_read_id>runspot_private.friend_chat_reads.last_read_id;
  return runspot_private.friend_chat_last_read(viewer,friend_chat_mark_read.peer_id);
end;
$$;
create function public.friend_chat_mark_read(peer_id uuid,last_id bigint)
returns bigint language sql security invoker set search_path='' as $$
  select runspot_private.friend_chat_mark_read(peer_id,last_id);
$$;
revoke all on function runspot_private.friend_chat_mark_read(uuid,bigint),public.friend_chat_mark_read(uuid,bigint)
  from public,anon,authenticated;
grant execute on function runspot_private.friend_chat_mark_read(uuid,bigint),public.friend_chat_mark_read(uuid,bigint)
  to authenticated;
notify pgrst,'reload schema';
