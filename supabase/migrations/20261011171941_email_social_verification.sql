-- 이메일 소유 확인은 서버 인증 원본에서만 읽고 사용자 메타데이터는 신뢰하지 않습니다.
create function runspot_private.email_verified(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from auth.users u where u.id=target
      and nullif(btrim(u.email),'') is not null
      and u.email_confirmed_at is not null
      and coalesce(u.email_change,'')=''
      and not coalesce(u.is_anonymous,false)
  );
$$;
revoke all on function runspot_private.email_verified(uuid) from public,anon,authenticated;

create function runspot_private.my_email_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.email_verified(auth.uid());
$$;
create function public.my_email_verified()
returns boolean language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_email_verified();
$$;
revoke all on function runspot_private.my_email_verified(),public.my_email_verified()
  from public,anon,authenticated;
grant execute on function runspot_private.my_email_verified(),public.my_email_verified() to authenticated;

create or replace function runspot_private.can_interact()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and runspot_private.is_active(auth.uid())
    and runspot_private.email_verified(auth.uid())
    and exists(select 1 from public.profiles where id=auth.uid() and nickname is not null);
$$;

create or replace function runspot_private.enforce_visibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility<>'private' and (not runspot_private.email_verified(new.id) or new.nickname is null) then
    raise exception '이메일 인증과 닉네임 등록 후 공개 범위를 변경할 수 있습니다.' using errcode='42501';
  end if;
  return new;
end;
$$;

create or replace function runspot_private.validate_nickname()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='UPDATE' and new.nickname is not distinct from old.nickname then
    new.nickname_changed_at=old.nickname_changed_at;
    return new;
  end if;
  if new.nickname is null then
    if tg_op='UPDATE' and old.nickname is not null then
      raise exception '등록된 닉네임은 삭제할 수 없습니다.' using errcode='22023';
    end if;
    new.nickname_changed_at=null;
    return new;
  end if;
  if not runspot_private.is_active(new.id) or not runspot_private.email_verified(new.id) then
    raise exception '가입과 이메일 인증을 완료해 주세요.' using errcode='42501';
  end if;
  if new.nickname !~ '^[가-힣A-Za-z0-9_]{2,30}$' then
    raise exception '닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.' using errcode='22023';
  end if;
  if tg_op='UPDATE' and old.nickname_changed_at>now()-interval '30 days' then
    raise exception '닉네임은 30일에 한 번 변경할 수 있습니다.' using errcode='P0001';
  end if;
  new.nickname_changed_at=now();
  return new;
end;
$$;

create or replace function runspot_private.set_my_nickname(requested_nickname text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  -- 이메일 변경과 닉네임 확정을 동시에 처리해 인증 상태가 엇갈리지 않도록 잠급니다.
  perform 1 from auth.users where id=auth.uid() for update;
  if not runspot_private.is_active(auth.uid()) or not runspot_private.email_verified(auth.uid()) then
    raise exception '가입과 이메일 인증을 완료해 주세요.' using errcode='42501';
  end if;
  if requested_nickname is null then raise exception '닉네임을 입력해 주세요.' using errcode='22023'; end if;
  update public.profiles set nickname=requested_nickname where id=auth.uid();
end;
$$;
revoke all on function runspot_private.set_my_nickname(text) from public,anon,authenticated;
grant execute on function runspot_private.set_my_nickname(text) to authenticated;
create or replace function public.set_my_nickname(requested_nickname text)
returns void language sql security invoker set search_path = '' as $$
  select runspot_private.set_my_nickname(requested_nickname);
$$;
revoke all on function public.set_my_nickname(text) from public,anon,authenticated;
grant execute on function public.set_my_nickname(text) to authenticated;

create or replace function runspot_private.can_view_location(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select target<>auth.uid() and runspot_private.can_interact()
    and runspot_private.email_verified(target)
    and exists (
      select 1 from public.profiles viewer, public.profiles subject
      where viewer.id=auth.uid() and subject.id=target
        and viewer.visibility<>'private' and subject.visibility<>'private'
        and runspot_private.can_read(target,subject.visibility)
        and (viewer.visibility='public' or exists (
          select 1 from public.friendships f where f.user_low=least(auth.uid(),target)
            and f.user_high=greatest(auth.uid(),target) and f.status='accepted'
        ))
    );
$$;

create or replace function runspot_private.publish_run(target_run uuid, content text, audience text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증이 필요합니다.' using errcode='42501';
  end if;
  insert into public.posts(run_id,user_id,caption,visibility,distance_m,duration_sec)
  select id,user_id,content,audience,distance_m,duration_sec from public.runs
  where id=target_run and user_id=auth.uid() and integrity_status='verified'
  returning id into result;
  if result is null then raise exception '공유할 수 없는 기록입니다.' using errcode='42501'; end if;
  return result;
end;
$$;

create or replace function runspot_private.search_friend(requested_nickname text)
returns table(user_id uuid, nickname text, relation text, relationship_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록을 완료해 주세요.' using errcode='42501';
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
    and runspot_private.is_active(p.id) and runspot_private.email_verified(p.id)
    and not exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=auth.uid() and b.blocked_id=p.id)
         or (b.blocked_id=auth.uid() and b.blocker_id=p.id))
  limit 1;
end;
$$;

create or replace function runspot_private.change_friend(target_id uuid, operation text, expected_id uuid)
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
  -- 이메일 변경, 계정 정지, 상호 요청 및 친구 수 제한을 일정한 잠금 순서로 보호합니다.
  perform 1 from auth.users where id in (low_id,high_id) order by id for share;
  perform 1 from runspot_private.account_controls where user_id in (low_id,high_id) order by user_id for share;
  perform 1 from public.profiles where id in (low_id,high_id) order by id for update;
  if not runspot_private.is_active(viewer) then
    raise exception '계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  select * into connection from public.friendships where user_low=low_id and user_high=high_id for update;

  if operation in ('request','accept') then
    if not runspot_private.can_interact() or not runspot_private.is_active(target_id)
      or not runspot_private.email_verified(target_id)
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

create or replace function runspot_private.update_my_live_location(
  latitude double precision, longitude double precision, accuracy_m double precision
) returns void language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  previous_update timestamptz;
begin
  if owner_id is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  -- 계정과 공개 설정을 잠근 뒤 인증 및 공개 범위를 검사합니다.
  perform 1 from auth.users where id=owner_id for update;
  perform 1 from public.profiles where id=owner_id for update;
  if owner_id is null or not runspot_private.can_interact() or not exists (
    select 1 from public.profiles where id=owner_id and visibility<>'private'
  ) then
    raise exception '이메일 인증과 닉네임 등록 후 프로필을 친구 또는 전체 공개로 설정해 주세요.'
      using errcode='42501';
  end if;
  if latitude is null or longitude is null or accuracy_m is null
    or not latitude between -90 and 90 or not longitude between -180 and 180
    or not accuracy_m between 0 and 100 then
    raise exception '정확한 현재 위치가 필요합니다.' using errcode='22023';
  end if;
  -- 계정별로 직렬화하여 동시 요청도 갱신 간격 제한을 지킵니다.
  select updated_at into previous_update from runspot_private.live_locations where user_id=owner_id;
  if previous_update > clock_timestamp()-interval '3 seconds' then return; end if;
  insert into runspot_private.live_locations(user_id,latitude,longitude,updated_at)
    values(owner_id,latitude,longitude,clock_timestamp())
    on conflict(user_id) do update set latitude=excluded.latitude,
      longitude=excluded.longitude,updated_at=excluded.updated_at;
end;
$$;

-- 인증 해제·이메일 변경 시 공개 위치를 즉시 회수하며 재인증 후 자동 공개하지 않습니다.
create or replace function runspot_private.reset_unverified_visibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not runspot_private.email_verified(new.id) or new.email is distinct from old.email then
    update public.profiles set visibility='private' where id=new.id and visibility<>'private';
  end if;
  return new;
end;
$$;
drop trigger reset_phone_visibility on auth.users;
create trigger reset_email_visibility
after update of email,email_confirmed_at,email_change,is_anonymous on auth.users
for each row execute function runspot_private.reset_unverified_visibility();
drop trigger require_phone_for_visibility on public.profiles;
create trigger require_email_for_visibility before insert or update on public.profiles
for each row execute function runspot_private.enforce_visibility();

-- 기존 공개 범위를 확대하지 않고 새 인증 기준에 맞지 않는 계정만 비공개로 돌립니다.
update public.profiles set visibility='private'
where visibility<>'private' and not runspot_private.email_verified(id);

drop function public.my_phone_verified();
drop function runspot_private.phone_verified(uuid);
notify pgrst, 'reload schema';

