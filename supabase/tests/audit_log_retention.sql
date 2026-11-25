begin;
insert into runspot_private.audit_logs(action, created_at, retention_hold_until) values
  ('audit_expired', now() - interval '181 days', null),
  ('audit_recent', now() - interval '179 days', null),
  ('audit_held', now() - interval '181 days', 'infinity'),
  ('audit_hold_released', now() - interval '181 days', now() - interval '1 day');

do $$
begin
  if runspot_private.purge_expired_audit_logs() <> 2
     or runspot_private.purge_expired_audit_logs() <> 0 then
    raise exception '기한이 지난 감사기록만 한 번 파기해야 합니다.';
  end if;
  if (select count(*) from runspot_private.audit_logs
      where action in ('audit_recent', 'audit_held')) <> 2 then
    raise exception '최근 기록과 보존 예외를 파기하면 안 됩니다.';
  end if;
  if has_function_privilege('service_role', 'runspot_private.purge_expired_audit_logs()', 'EXECUTE') then
    raise exception '서비스 역할이 감사기록 파기 함수를 직접 실행할 수 있습니다.';
  end if;
end;
$$;
rollback;
