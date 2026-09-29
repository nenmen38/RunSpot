-- 기본값은 비활성입니다. 개발 프로젝트에서만 운영자가 만료 시각을 지정합니다.
create table runspot_private.registration_test_settings (
  singleton boolean primary key default true check(singleton),
  enabled_until timestamptz
);
insert into runspot_private.registration_test_settings(singleton) values(true);
create table runspot_private.test_registrations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
revoke all on runspot_private.registration_test_settings, runspot_private.test_registrations
  from public,anon,authenticated;

create function public.registration_test_mode()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.registration_test_settings where enabled_until>now());
$$;
create function public.complete_test_registration()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.registration_test_mode()
    or not exists(select 1 from runspot_private.account_controls where user_id=auth.uid() and status='active') then
    raise exception '테스트 가입이 허용되지 않습니다.' using errcode='42501';
  end if;
  -- 실제 약관 동의 및 정식 가입 완료 시각은 만들지 않습니다.
  insert into runspot_private.test_registrations(user_id) values(auth.uid()) on conflict do nothing;
end;
$$;
create or replace function public.my_registration_complete()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles where id=auth.uid() and registration_completed_at is not null)
    or (public.registration_test_mode() and exists(select 1 from runspot_private.test_registrations where user_id=auth.uid()));
$$;
create or replace function runspot_private.is_active(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.account_controls c join public.profiles p on p.id=c.user_id
    where c.user_id=target and c.status='active' and (
      p.registration_completed_at is not null or (
        public.registration_test_mode() and exists(select 1 from runspot_private.test_registrations t where t.user_id=target)
      )
    ));
$$;
revoke all on function public.registration_test_mode(), public.complete_test_registration() from public,anon,authenticated;
grant execute on function public.registration_test_mode() to anon,authenticated;
grant execute on function public.complete_test_registration() to authenticated;
