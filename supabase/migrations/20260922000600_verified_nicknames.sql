-- 기본 가입과 전화번호 인증 후 닉네임 확정을 분리합니다.
drop function public.complete_registration(text,uuid);
drop function runspot_private.finish_registration(uuid,text,uuid);
create function runspot_private.finish_registration(target uuid, accepted_terms uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.profiles where id=target for update;
  if not found or not exists(select 1 from runspot_private.account_controls where user_id=target and status='active') then
    raise exception '가입을 완료할 수 없는 계정입니다.' using errcode='42501';
  end if;
  if exists(select 1 from public.profiles where id=target and registration_completed_at is not null) then return; end if;
  perform 1 from public.registration_terms where id=accepted_terms and is_current and published_at<=now() for share;
  if not found then raise exception '현재 약관에 동의해 주세요.' using errcode='22023'; end if;
  update public.profiles set registration_completed_at=now() where id=target;
  insert into runspot_private.registration_consents(user_id,terms_id) values(target,accepted_terms);
end;
$$;
create function public.complete_registration(accepted_terms uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  perform runspot_private.finish_registration(auth.uid(),accepted_terms);
end;
$$;
create or replace function runspot_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id);
  insert into runspot_private.account_controls(user_id) values(new.id);
  -- 가입 메타데이터의 닉네임은 무시하여 미인증 선점을 막습니다.
  if new.raw_user_meta_data->>'registration_terms_id' is not null then
    perform runspot_private.finish_registration(new.id,(new.raw_user_meta_data->>'registration_terms_id')::uuid);
  end if;
  return new;
end;
$$;

alter table public.profiles add column nickname_changed_at timestamptz;
revoke update(nickname) on public.profiles from authenticated;
drop trigger validate_nickname on public.profiles;
-- 이전 정책에서 미인증 상태로 선점한 이름은 해제하고 인증된 이름은 유지합니다.
update public.profiles set nickname=null where nickname is not null and not runspot_private.phone_verified(id);
update public.profiles set nickname_changed_at=now() where nickname is not null;

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
  if not runspot_private.is_active(new.id) or not runspot_private.phone_verified(new.id) then
    raise exception '가입과 전화번호 인증을 완료해 주세요.' using errcode='42501';
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
create trigger validate_nickname before insert or update of nickname,nickname_changed_at on public.profiles
for each row execute function runspot_private.validate_nickname();

create function public.set_my_nickname(requested_nickname text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  -- 번호 변경과 닉네임 확정을 동시에 처리해 인증 상태가 엇갈리지 않도록 잠급니다.
  perform 1 from auth.users where id=auth.uid() for update;
  if not runspot_private.is_active(auth.uid()) or not runspot_private.phone_verified(auth.uid()) then
    raise exception '가입과 전화번호 인증을 완료해 주세요.' using errcode='42501';
  end if;
  if requested_nickname is null then raise exception '닉네임을 입력해 주세요.' using errcode='22023'; end if;
  update public.profiles set nickname=requested_nickname where id=auth.uid();
end;
$$;

create or replace function runspot_private.can_interact()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and runspot_private.is_active(auth.uid())
    and runspot_private.phone_verified(auth.uid())
    and exists(select 1 from public.profiles where id=auth.uid() and nickname is not null);
$$;
create or replace function runspot_private.enforce_visibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility<>'private' and (not runspot_private.phone_verified(new.id) or new.nickname is null) then
    raise exception '전화번호 인증과 닉네임 등록 후 공개 범위를 변경할 수 있습니다.' using errcode='42501';
  end if;
  return new;
end;
$$;
update public.profiles set visibility='private' where nickname is null;
revoke all on function runspot_private.finish_registration(uuid,uuid) from public,anon,authenticated;
revoke all on function public.complete_registration(uuid), public.set_my_nickname(text) from public,anon,authenticated;
grant execute on function public.complete_registration(uuid), public.set_my_nickname(text) to authenticated;
