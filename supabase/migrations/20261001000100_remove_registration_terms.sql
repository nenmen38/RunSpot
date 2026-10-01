-- 가입 과정에서 약관 동의 단계를 제거합니다.
drop function if exists public.complete_registration(uuid);
drop function if exists public.complete_registration(text, uuid);
drop function if exists runspot_private.finish_registration(uuid, uuid);
drop function if exists runspot_private.finish_registration(uuid, text, uuid);
drop trigger if exists protect_published_terms on public.registration_terms;
drop function if exists runspot_private.protect_published_terms();
drop table if exists runspot_private.registration_consents;
drop table if exists public.registration_terms;

create function runspot_private.finish_registration(target uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- 가입 완료 처리는 사용자별로 직렬화합니다.
  perform 1 from public.profiles where id=target for update;
  if not found or not exists(select 1 from runspot_private.account_controls where user_id=target and status='active') then
    raise exception '가입을 완료할 수 없는 계정입니다.' using errcode='42501';
  end if;
  if exists(select 1 from public.profiles where id=target and registration_completed_at is not null) then
    return;
  end if;
  update public.profiles set registration_completed_at=now() where id=target;
end;
$$;

create function public.complete_registration()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  perform runspot_private.finish_registration(auth.uid());
end;
$$;

create or replace function runspot_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id);
  insert into runspot_private.account_controls(user_id) values(new.id);
  perform runspot_private.finish_registration(new.id);
  return new;
end;
$$;

revoke all on function runspot_private.finish_registration(uuid) from public, anon, authenticated;
revoke all on function public.complete_registration() from public, anon, authenticated;
grant execute on function public.complete_registration() to authenticated;
