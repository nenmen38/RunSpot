-- 선택 전화번호 인증 상태는 본인만 조회하며 이메일 기반 소셜 권한과 분리합니다.
create function runspot_private.my_phone_verification_state()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'phone',nullif(btrim(u.phone),''),
    'pending_phone',nullif(btrim(u.phone_change),''),
    'verified',nullif(btrim(u.phone),'') is not null
      and u.phone_confirmed_at is not null and coalesce(u.phone_change,'')=''
      and not coalesce(u.is_anonymous,false)
  ) into result from auth.users u where u.id=auth.uid();
  if result is null then raise exception '계정을 확인하지 못했습니다.' using errcode='42501'; end if;
  return result;
end;
$$;
create function public.my_phone_verification_state()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_phone_verification_state();
$$;
revoke all on function runspot_private.my_phone_verification_state(),public.my_phone_verification_state()
  from public,anon,authenticated;
grant execute on function runspot_private.my_phone_verification_state(),public.my_phone_verification_state()
  to authenticated;
notify pgrst, 'reload schema';
