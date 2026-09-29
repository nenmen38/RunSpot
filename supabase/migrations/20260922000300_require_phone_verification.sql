-- 전화번호와 확인 시각은 사용자가 수정 가능한 메타데이터에서 읽지 않습니다.
create function runspot_private.phone_verified(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u where u.id=target
      and nullif(u.phone,'') is not null
      and u.phone_confirmed_at is not null
      and coalesce(u.phone_change,'')=''
  );
$$;
revoke all on function runspot_private.phone_verified(uuid) from public, anon, authenticated;

create or replace function runspot_private.is_active(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.phone_verified(target) and exists (
    select 1 from runspot_private.account_controls where user_id=target and status='active'
  );
$$;

-- 인증 화면에서 본인의 확인 여부만 조회할 수 있습니다.
create function public.my_phone_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.phone_verified(auth.uid());
$$;
revoke all on function public.my_phone_verified() from public, anon, authenticated;
grant execute on function public.my_phone_verified() to authenticated;
