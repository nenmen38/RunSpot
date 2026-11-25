begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000561');

insert into runspot_private.board_reports(post_id, reporter_id, snapshot, reason, status, resolved_at)
values (gen_random_uuid(), '00000000-0000-4000-8000-000000000561',
        '{"images":["orphan.jpg"],"body":"신고 원문"}', '증빙', 'removed', now() - interval '91 days');

insert into runspot_private.moderation_cases(kind, evidence, photo, reason, status, resolved_at) values
  ('chat', '{"body":"파기 대상"}', decode('ffff','hex'), '만료', 'removed', now() - interval '91 days'),
  ('avatar', '{"body":"미처리"}', decode('ffff','hex'), '미처리', 'open', null),
  ('chat', '{"body":"최근 처리"}', decode('ffff','hex'), '최근', 'removed', now() - interval '89 days'),
  ('chat', '{"body":"이의 제기"}', decode('ffff','hex'), '이의', 'actioned', now() - interval '91 days');
insert into runspot_private.moderation_actions(case_id, kind, reason, appeal_status)
select id, 'warning', '이의 확인', 'pending'
from runspot_private.moderation_cases where reason = '이의';

do $$
begin
  if runspot_private.purge_expired_report_evidence() <> 2 then
    raise exception '만료된 신고 증빙 두 건만 파기해야 합니다.';
  end if;
  if exists (select 1 from runspot_private.moderation_cases
             where reason in ('증빙', '만료') and (evidence <> '{}' or photo is not null))
     or exists (select 1 from runspot_private.board_reports
                where reason = '증빙' and snapshot <> '{}')
     or exists (select 1 from runspot_private.moderation_cases
                where reason in ('미처리', '최근', '이의') and photo is null)
     or runspot_private.purge_expired_report_evidence() <> 0 then
    raise exception '운영 신고 증빙의 보관·파기 결과가 올바르지 않습니다.';
  end if;
end;
$$;
rollback;
