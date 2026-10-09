-- 친구 관계는 서버 함수로만 변경하고 오래된 화면의 요청을 식별자로 구분합니다.
alter table public.friendships add column relationship_id uuid not null default gen_random_uuid();
create unique index friendships_relationship_id on public.friendships(relationship_id);

create table runspot_private.friend_request_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  sent_count integer not null check (sent_count between 1 and 30),
  last_sent_at timestamptz not null
);
alter table runspot_private.friend_request_limits enable row level security;
revoke all on runspot_private.friend_request_limits from public, anon, authenticated;
grant select, insert, update, delete on runspot_private.friend_request_limits to service_role;

create function runspot_private.friend_entries()
returns table(user_id uuid, nickname text, relation text, relationship_id uuid, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.nickname,
    case when f.status='accepted' then 'friend'
      when f.requested_by=auth.uid() then 'sent' else 'received' end,
    f.relationship_id, f.created_at
  from public.friendships f
  join public.profiles p on p.id=case when f.user_low=auth.uid() then f.user_high else f.user_low end
  where auth.uid() is not null and runspot_private.is_active(auth.uid())
    and auth.uid() in (f.user_low,f.user_high)
    and runspot_private.is_active(p.id) and p.nickname is not null
    and not exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=auth.uid() and b.blocked_id=p.id)
         or (b.blocked_id=auth.uid() and b.blocker_id=p.id))
  order by f.created_at desc, p.id;
$$;

create function runspot_private.friend_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return jsonb_build_object(
    'can_interact',runspot_private.can_interact(),
    'entries',coalesce((select jsonb_agg(to_jsonb(e)) from runspot_private.friend_entries() e),'[]'::jsonb)
  );
end;
$$;

create function runspot_private.search_friend(requested_nickname text)
returns table(user_id uuid, nickname text, relation text, relationship_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not runspot_private.can_interact() then
    raise exception '전화번호 인증과 닉네임 등록을 완료해 주세요.' using errcode='42501';
  end if;
  if requested_nickname is null or requested_nickname !~ '^[가-힣A-Za-z0-9_]{2,30}$' then
    raise exception '닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.' using errcode='22023';
  end if;
  -- 전체 사용자 목록이나 비공개 계정을 노출하지 않고 고유 닉네임만 조회합니다.
  return query
  select p.id,p.nickname,
    case when f.status='accepted' then 'friend'
      when f.requested_by=auth.uid() then 'sent'
      when f.status='pending' then 'received' else 'none' end,
    f.relationship_id,f.created_at
  from public.profiles p
  left join public.friendships f on f.user_low=least(auth.uid(),p.id) and f.user_high=greatest(auth.uid(),p.id)
  where lower(p.nickname)=lower(requested_nickname) and p.id<>auth.uid()
    and (p.visibility<>'private' or f.relationship_id is not null)
    and runspot_private.is_active(p.id) and runspot_private.phone_verified(p.id)
    and not exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=auth.uid() and b.blocked_id=p.id)
         or (b.blocked_id=auth.uid() and b.blocker_id=p.id))
  limit 1;
end;
$$;

create function runspot_private.change_friend(target_id uuid, operation text, expected_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  low_id uuid;
  high_id uuid;
  connection public.friendships%rowtype;
  quota runspot_private.friend_request_limits%rowtype;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if target_id is null or target_id=viewer or operation is null
      or operation not in ('request','accept','reject','cancel','remove') then
    raise exception '올바른 친구 작업을 선택해 주세요.' using errcode='22023';
  end if;
  low_id := least(viewer,target_id);
  high_id := greatest(viewer,target_id);
  -- 번호 변경, 계정 정지, 상호 요청 및 친구 수 제한을 일정한 잠금 순서로 보호합니다.
  perform 1 from auth.users where id in (low_id,high_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (low_id,high_id) order by user_id for share;
  perform 1 from public.profiles where id in (low_id,high_id) order by id for update;
  if not runspot_private.is_active(viewer) then
    raise exception '계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  select * into connection from public.friendships where user_low=low_id and user_high=high_id for update;

  if operation in ('request','accept') then
    if not runspot_private.can_interact() or not runspot_private.is_active(target_id)
      or not runspot_private.phone_verified(target_id)
      or not exists(select 1 from public.profiles where id=target_id and nickname is not null)
      or exists(select 1 from runspot_private.blocks b
        where (b.blocker_id=viewer and b.blocked_id=target_id)
           or (b.blocked_id=viewer and b.blocker_id=target_id)) then
      raise exception '인증 상태를 확인하거나 친구 목록을 새로고침해 주세요.' using errcode='42501';
    end if;
  end if;

  if operation='request' then
    if connection.relationship_id is not null then
      -- 중복 전송은 무해하지만 상호 요청을 수락으로 간주하지 않습니다.
      return;
    end if;
    if not exists(select 1 from public.profiles where id=target_id and visibility<>'private') then
      raise exception '요청할 수 없는 사용자입니다.' using errcode='42501';
    end if;
    if (select count(*) from public.friendships where viewer in (user_low,user_high))>=500
      or (select count(*) from public.friendships where target_id in (user_low,user_high))>=500 then
      raise exception '친구와 요청은 계정당 최대 500개입니다.' using errcode='P0001';
    end if;
    select * into quota from runspot_private.friend_request_limits where user_id=viewer for update;
    if quota.last_sent_at>now()-interval '5 seconds' then
      raise exception '잠시 후 친구 요청을 보내 주세요.' using errcode='P0001';
    end if;
    if quota.window_started_at>now()-interval '1 hour' and quota.sent_count>=30 then
      raise exception '친구 요청은 한 시간에 30번까지 보낼 수 있습니다.' using errcode='P0001';
    end if;
    insert into runspot_private.friend_request_limits(user_id,window_started_at,sent_count,last_sent_at)
    values(viewer,now(),1,now())
    on conflict(user_id) do update set
      window_started_at=case when quota.window_started_at<=now()-interval '1 hour' then now() else quota.window_started_at end,
      sent_count=case when quota.window_started_at<=now()-interval '1 hour' then 1 else quota.sent_count+1 end,
      last_sent_at=now();
    insert into public.friendships(user_low,user_high,requested_by) values(low_id,high_id,viewer);
    return;
  end if;

  if expected_id is null or connection.relationship_id is distinct from expected_id then
    raise exception '친구 상태가 변경되었습니다. 새로고침해 주세요.' using errcode='P0001';
  end if;
  if operation='accept' then
    if connection.requested_by=viewer then
      raise exception '받은 요청만 수락할 수 있습니다.' using errcode='42501';
    end if;
    update public.friendships set status='accepted' where relationship_id=expected_id;
  elsif operation='reject' then
    if connection.status<>'pending' or connection.requested_by=viewer then
      raise exception '받은 요청만 거절할 수 있습니다.' using errcode='42501';
    end if;
    delete from public.friendships where relationship_id=expected_id;
  elsif operation='cancel' then
    if connection.status<>'pending' or connection.requested_by<>viewer then
      raise exception '보낸 요청만 취소할 수 있습니다.' using errcode='42501';
    end if;
    delete from public.friendships where relationship_id=expected_id;
  elsif operation='remove' then
    if connection.status<>'accepted' then
      raise exception '친구 관계만 삭제할 수 있습니다.' using errcode='42501';
    end if;
    delete from public.friendships where relationship_id=expected_id;
  end if;
end;
$$;

-- 비공개 구현만 제한적으로 권한을 가지며 공개 함수는 호출자 권한으로 연결합니다.
revoke all on function runspot_private.friend_entries(),runspot_private.friend_dashboard(),
  runspot_private.search_friend(text),runspot_private.change_friend(uuid,text,uuid) from public,anon,authenticated;
grant execute on function runspot_private.friend_dashboard(),runspot_private.search_friend(text),
  runspot_private.change_friend(uuid,text,uuid) to authenticated;
create function public.friend_dashboard()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.friend_dashboard();
$$;
create function public.search_friend(requested_nickname text)
returns table(user_id uuid,nickname text,relation text,relationship_id uuid,created_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select * from runspot_private.search_friend(requested_nickname);
$$;
create function public.change_friend(target_id uuid,operation text,expected_id uuid default null)
returns void language sql security invoker set search_path = '' as $$
  select runspot_private.change_friend(target_id,operation,expected_id);
$$;
revoke all on function public.friend_dashboard(),public.search_friend(text),public.change_friend(uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function public.friend_dashboard(),public.search_friend(text),public.change_friend(uuid,text,uuid)
  to authenticated;
notify pgrst, 'reload schema';
