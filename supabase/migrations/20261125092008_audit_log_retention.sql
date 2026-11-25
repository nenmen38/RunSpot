-- 감사기록은 완료된 관리자 조치와 탈퇴 처리 시점부터 180일 보관합니다.
-- 법정 보존과 진행 중 분쟁은 관련 기록에만 별도 보존 기한을 등록합니다.
alter table runspot_private.audit_logs add column retention_hold_until timestamptz;
create index audit_logs_retention on runspot_private.audit_logs (created_at, id);

create function runspot_private.purge_expired_audit_logs()
returns integer language sql set search_path = '' as $$
  with expired as materialized (
    select id from runspot_private.audit_logs
    where created_at <= now() - interval '180 days'
      and (retention_hold_until is null or retention_hold_until <= now())
    order by created_at, id
    limit 500
    for update skip locked
  ), purged as (
    delete from runspot_private.audit_logs a using expired
    where a.id = expired.id
    returning a.id
  )
  select count(*)::integer from purged;
$$;
revoke all on function runspot_private.purge_expired_audit_logs()
from public, anon, authenticated, service_role;

select cron.schedule(
  'runspot-audit-log-retention',
  '37 * * * *',
  'select runspot_private.purge_expired_audit_logs();'
);
