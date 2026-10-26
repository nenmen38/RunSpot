-- 새 숨김·신고 데이터가 있으면 자동 복구하지 않습니다. 편집한 본문은 보존합니다.
begin;
lock table public.runs in access exclusive mode;
lock table runspot_private.board_posts in access exclusive mode;
lock table runspot_private.board_reports in access exclusive mode;
do $$ begin
 if exists(select 1 from public.runs where hidden) or exists(select 1 from runspot_private.board_reports) then
  raise exception '새 사용자 설정 또는 신고가 있어 자동 복구를 중단합니다.';
 end if;
end; $$;
create or replace function runspot_private.my_run_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 개인 통계는 검증 여부와 관계없이 저장된 모든 완료 기록을 집계합니다.
  -- 이동 거리나 활동 시간이 없는 기록은 페이스 계산에서만 제외합니다.
  return (
    select jsonb_build_object(
      'week_started_at', week_start,
      'weekly_distance_m', coalesce(sum(r.distance_m) filter (
        where r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
          and r.ended_at <= now()), 0),
      'completed_runs', count(*),
      'pace_distance_m', coalesce(sum(r.distance_m) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0),
      'pace_duration_sec', coalesce(sum(r.duration_sec) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0)
    ) from public.runs r where r.user_id=viewer and r.ended_at <= now()
  );
end;
$$;
create or replace function runspot_private.board_post_json(p runspot_private.board_posts,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p.id,'board',p.board,'topic',p.topic,'region',p.region,'title',p.title,'body',p.body,
    'nickname',coalesce((select nickname from public.profiles where id=p.author_id),'닉네임 없음'),
    'is_mine',p.author_id=viewer,'race_date',p.race_date,'race_place',p.race_place,'race_url',p.race_url,
    'created_at',p.created_at);
$$;
drop function public.set_my_run_hidden(uuid,boolean);
drop function runspot_private.set_my_run_hidden(uuid,boolean);
drop function public.can_access_management();
drop function runspot_private.can_access_management();
drop function public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text);
drop function runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text);
drop function public.report_board_post(uuid,text);
drop function runspot_private.report_board_post(uuid,text);
drop function public.board_report_cases();
drop function runspot_private.board_report_cases();
drop function public.resolve_board_report(uuid,text,text);
drop function runspot_private.resolve_board_report(uuid,text,text);
drop table runspot_private.board_reports;
alter table runspot_private.board_posts drop column updated_at;
alter table public.runs drop column hidden;
notify pgrst,'reload schema';
commit;
