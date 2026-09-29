-- 실제 약관은 운영자가 검토한 본문만 등록합니다. 예시 약관은 게시하지 않습니다.
create table public.registration_terms (
  id uuid primary key default gen_random_uuid(),
  version text not null unique check (length(btrim(version)) > 0),
  title text not null check (length(btrim(title)) > 0),
  body text not null check (length(btrim(body)) > 0),
  published_at timestamptz,
  is_current boolean not null default false,
  check (not is_current or published_at is not null)
);
create unique index registration_terms_current on public.registration_terms(is_current) where is_current;
alter table public.registration_terms enable row level security;
revoke all on public.registration_terms from public, anon, authenticated;
grant select on public.registration_terms to anon, authenticated;
grant all on public.registration_terms to service_role;
create policy published_terms_read on public.registration_terms for select to anon, authenticated
using (published_at is not null and published_at <= now());

create function runspot_private.protect_published_terms()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.published_at is not null then
    if tg_op = 'DELETE' then
      raise exception '게시된 약관은 삭제할 수 없습니다.';
    end if;
    if row(new.id,new.version,new.title,new.body,new.published_at)
      is distinct from row(old.id,old.version,old.title,old.body,old.published_at) then
      raise exception '게시된 약관은 새 버전으로 등록해야 합니다.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger protect_published_terms before update or delete on public.registration_terms
for each row execute function runspot_private.protect_published_terms();

alter table public.profiles add column registration_completed_at timestamptz;
create table runspot_private.registration_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms_id uuid not null references public.registration_terms(id),
  accepted_at timestamptz not null default now()
);
revoke all on runspot_private.registration_consents from public, anon, authenticated;

create function runspot_private.validate_nickname()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.nickname is not null and new.nickname !~ '^[가-힣A-Za-z0-9_]{2,30}$' then
    raise exception '닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.' using errcode='22023';
  end if;
  if new.nickname is null and new.registration_completed_at is not null then
    raise exception '닉네임은 필수입니다.' using errcode='22023';
  end if;
  return new;
end;
$$;
create trigger validate_nickname before insert or update of nickname on public.profiles
for each row execute function runspot_private.validate_nickname();

create function runspot_private.finish_registration(target uuid, requested_nickname text, accepted_terms uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- 가입 완료 처리는 사용자별로 직렬화하며 기존 동의 시각을 덮어쓰지 않습니다.
  perform 1 from public.profiles where id=target for update;
  if not found or not exists(select 1 from runspot_private.account_controls where user_id=target and status='active') then
    raise exception '가입을 완료할 수 없는 계정입니다.' using errcode='42501';
  end if;
  if exists(select 1 from public.profiles where id=target and registration_completed_at is not null) then
    return;
  end if;
  if requested_nickname is null or requested_nickname !~ '^[가-힣A-Za-z0-9_]{2,30}$' then
    raise exception '닉네임은 한글, 영문, 숫자, 밑줄로 2~30자 입력해 주세요.' using errcode='22023';
  end if;
  perform 1 from public.registration_terms where id=accepted_terms and is_current
    and published_at <= now() for share;
  if not found then
    raise exception '현재 약관을 확인하고 동의해 주세요.' using errcode='22023';
  end if;
  update public.profiles set nickname=requested_nickname, registration_completed_at=now() where id=target;
  insert into runspot_private.registration_consents(user_id,terms_id) values(target,accepted_terms);
end;
$$;

create function public.complete_registration(requested_nickname text, accepted_terms uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  perform runspot_private.finish_registration(auth.uid(),requested_nickname,accepted_terms);
end;
$$;
create function public.my_registration_complete()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles where id=auth.uid() and registration_completed_at is not null);
$$;

create or replace function runspot_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id);
  insert into runspot_private.account_controls(user_id) values(new.id);
  -- 메타데이터는 요청 값으로만 사용하며, 완료 여부와 동의 시각은 서버에서 결정합니다.
  if new.raw_user_meta_data->>'registration_terms_id' is not null then
    perform runspot_private.finish_registration(new.id,
      new.raw_user_meta_data->>'registration_nickname',
      (new.raw_user_meta_data->>'registration_terms_id')::uuid);
  end if;
  return new;
end;
$$;

create or replace function runspot_private.is_active(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.account_controls c join public.profiles p on p.id=c.user_id
    where c.user_id=target and c.status='active' and p.registration_completed_at is not null);
$$;
revoke all on function runspot_private.protect_published_terms(), runspot_private.validate_nickname(),
  runspot_private.finish_registration(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.complete_registration(text,uuid), public.my_registration_complete() from public, anon, authenticated;
grant execute on function public.complete_registration(text,uuid), public.my_registration_complete() to authenticated;
