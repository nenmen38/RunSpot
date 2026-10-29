-- 앱의 자동 대회 조회를 제거한 뒤 사용합니다. 사용자 게시판 자료와 공유 확장은 유지합니다.
begin;
select cron.unschedule(jobid) from cron.job where jobname='runspot-marathons-daily';
drop function if exists runspot_private.refresh_marathons();
drop function if exists public.marathon_events();
drop function if exists runspot_private.marathon_events();
drop function if exists runspot_private.import_marathons(jsonb);
drop function if exists runspot_private.marathon_status(jsonb,date,timestamptz);
drop table if exists runspot_private.marathon_catalog;
drop table if exists runspot_private.marathon_sync_state;
commit;
