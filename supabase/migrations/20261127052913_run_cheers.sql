-- 러닝 중 친구 응원: 지금 달리고 있는(위치를 공유 중인) 친구에게 '응원'을 보내면,
-- 받는 사람 앱이 러닝 중에 가져가 "OO님이 응원을 보냈어요"라고 음성으로 읽어 줍니다.
create table runspot_private.run_cheers (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  heard_at timestamptz,
  check (sender_id <> recipient_id)
);
create index run_cheers_recipient on runspot_private.run_cheers(recipient_id, created_at desc) where heard_at is null;
create index run_cheers_sender on runspot_private.run_cheers(sender_id, recipient_id, created_at desc);
alter table runspot_private.run_cheers enable row level security;
revoke all on runspot_private.run_cheers from public, anon, authenticated;

-- 응원 보내기: 친구이고, 상대가 2분 안에 위치를 보낸(달리는 중) 경우만 됩니다. 같은 친구에게는 1분에 한 번.
create function runspot_private.send_cheer(target uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if target is null or target = viewer or not exists(
    select 1 from public.friendships f
    where f.user_low = least(viewer, target) and f.user_high = greatest(viewer, target) and f.status = 'accepted'
  ) or exists(select 1 from runspot_private.blocks b
    where (b.blocker_id = viewer and b.blocked_id = target) or (b.blocker_id = target and b.blocked_id = viewer)) then
    raise exception '친구에게만 응원을 보낼 수 있어요.' using errcode = '42501';
  end if;
  if not exists(select 1 from runspot_private.live_locations l
    where l.user_id = target and l.updated_at > now() - interval '2 minutes') then
    raise exception '지금 달리고 있는 친구에게만 응원할 수 있어요.' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('cheer:' || viewer::text || target::text, 0));
  if exists(select 1 from runspot_private.run_cheers c
    where c.sender_id = viewer and c.recipient_id = target and c.created_at > now() - interval '1 minute') then
    raise exception '방금 응원을 보냈어요. 잠시 뒤에 다시 보내 주세요.' using errcode = 'P0001';
  end if;
  insert into runspot_private.run_cheers(sender_id, recipient_id) values (viewer, target);
end;
$$;
create function public.send_cheer(target uuid)
returns void language sql security invoker set search_path = ''
as $$ select runspot_private.send_cheer(target); $$;

-- 받은 응원 가져가기: 10분 안에 온 아직 듣지 않은 응원을 보낸 사람 닉네임과 함께 돌려주고 들은 것으로 표시합니다.
create function runspot_private.take_my_cheers()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); result jsonb;
begin
  with taken as (
    update runspot_private.run_cheers c set heard_at = now()
    where c.recipient_id = viewer and c.heard_at is null and c.created_at > now() - interval '10 minutes'
      and runspot_private.board_author_visible(c.sender_id, viewer)
    returning c.sender_id, c.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'sender_id', t.sender_id,
      'nickname', coalesce((select nullif(p.nickname, '') from public.profiles p where p.id = t.sender_id), '친구'),
      'at', t.created_at) order by t.created_at), '[]'::jsonb)
  into result from taken t;
  -- 하루 지난 응원 기록은 지웁니다.
  delete from runspot_private.run_cheers where created_at < now() - interval '1 day';
  return result;
end;
$$;
create function public.take_my_cheers()
returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.take_my_cheers(); $$;

revoke all on function runspot_private.send_cheer(uuid), public.send_cheer(uuid),
  runspot_private.take_my_cheers(), public.take_my_cheers() from public, anon, authenticated;
grant execute on function runspot_private.send_cheer(uuid), public.send_cheer(uuid),
  runspot_private.take_my_cheers(), public.take_my_cheers() to authenticated;
notify pgrst, 'reload schema';
