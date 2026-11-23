-- 기존 다중 인증을 통과한 관리자에게만 미처리 건수를 반환합니다.
create function runspot_private.admin_pending_notification_count()
returns bigint language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or runspot_private.staff_role() is distinct from 'admin' then
    return 0;
  end if;

  return (
    (select count(*) from runspot_private.moderation_cases where status = 'open')
    + (select count(*) from runspot_private.moderation_actions where appeal_status = 'pending')
    + (select count(*) from runspot_private.integrity_cases where status in ('open', 'evidence_requested'))
  );
end;
$$;

create function public.admin_pending_notification_count()
returns bigint language sql stable security invoker set search_path = '' as $$
  select runspot_private.admin_pending_notification_count();
$$;

revoke all on function public.admin_pending_notification_count(),
  runspot_private.admin_pending_notification_count() from public, anon, authenticated;
grant execute on function public.admin_pending_notification_count(),
  runspot_private.admin_pending_notification_count() to authenticated;

notify pgrst, 'reload schema';
