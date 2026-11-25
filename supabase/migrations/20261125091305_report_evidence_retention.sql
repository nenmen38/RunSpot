-- 검토가 끝난 신고의 원문과 첨부만 기한에 맞춰 파기합니다.
-- 처리 상태 및 제재 이력은 기존 운영 화면과 이의 제기 흐름에서 사용합니다.
alter table runspot_private.moderation_cases
  add column evidence_purged_at timestamptz;

create index moderation_cases_evidence_retention
  on runspot_private.moderation_cases(resolved_at, id)
  where resolved_at is not null and status <> 'open' and evidence_purged_at is null;

create function runspot_private.purge_expired_report_evidence()
returns integer language sql set search_path = '' as $$
  with expired as materialized (
    select c.id
    from runspot_private.moderation_cases c
    left join runspot_private.moderation_actions a on a.case_id = c.id
    where c.status <> 'open'
      and c.resolved_at < now() - interval '90 days'
      and c.evidence_purged_at is null
      and a.appeal_status is distinct from 'pending'
      and (a.appeal_resolved_at is null or a.appeal_resolved_at < now() - interval '90 days')
    order by c.resolved_at, c.id
    limit 500
    for update of c skip locked
  ), purged as (
    update runspot_private.moderation_cases c
    set evidence = '{}'::jsonb, photo = null, evidence_purged_at = now()
    from expired
    where c.id = expired.id
    returning c.board_report_id
  ), board_snapshots as (
    -- 사진 경로가 남아 있지 않으면 운영 작업자가 미사용 원본을 Storage API로 정리합니다.
    update runspot_private.board_reports r
    set snapshot = '{}'::jsonb
    from purged p
    where r.id = p.board_report_id
  )
  select count(*)::integer from purged;
$$;
revoke all on function runspot_private.purge_expired_report_evidence()
from public, anon, authenticated, service_role;

select cron.schedule(
  'runspot-report-evidence-retention',
  '17 * * * *',
  'select runspot_private.purge_expired_report_evidence();'
);
