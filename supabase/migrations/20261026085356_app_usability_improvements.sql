-- 숨김은 표시만 바꾸며 보상·업적·통계와 원본 자료를 변경하지 않습니다.
alter table public.runs add column hidden boolean not null default false;
create function runspot_private.set_my_run_hidden(requested_run_id uuid,requested_hidden boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
  raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
 end if;
 if requested_hidden is null then raise exception '표시 설정을 확인해 주세요.' using errcode='22023'; end if;
 update public.runs set hidden=requested_hidden where id=requested_run_id and user_id=auth.uid();
 if not found then raise exception '본인 기록만 변경할 수 있습니다.' using errcode='42501'; end if;
end;
$$;
create function public.set_my_run_hidden(requested_run_id uuid,requested_hidden boolean)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.set_my_run_hidden(requested_run_id,requested_hidden);
$$;
-- 메뉴 표시만 결정하며 실제 관리 RPC의 역할·다중 인증 검사를 대체하지 않습니다.
create function runspot_private.can_access_management()
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and runspot_private.is_active(auth.uid())
  and exists(select 1 from runspot_private.user_roles where user_id=auth.uid());
$$;
create function public.can_access_management()
returns boolean language sql stable security invoker set search_path='' as $$
 select runspot_private.can_access_management();
$$;
create or replace function runspot_private.my_run_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 개인 거리·페이스는 원본을 보존하고 완료 횟수만 업적과 같은 인정 기준을 따릅니다.
  return (
    select jsonb_build_object(
      'week_started_at', week_start,
      'weekly_distance_m', coalesce(sum(r.distance_m) filter (
        where r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
          and r.ended_at <= now()), 0),
      'completed_runs', count(*) filter(where r.distance_m>0 and r.duration_sec>0 and not r.review_pending and r.integrity_status<>'rejected'),
      'pace_distance_m', coalesce(sum(r.distance_m) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0),
      'pace_duration_sec', coalesce(sum(r.duration_sec) filter (
        where r.distance_m > 0 and r.duration_sec > 0), 0)
    ) from public.runs r where r.user_id=viewer and r.ended_at <= now()
  );
end;
$$;


-- 수정 충돌과 응답 유실 뒤 재시도를 구분합니다.
alter table runspot_private.board_posts add column updated_at timestamptz not null default now();
create or replace function runspot_private.board_post_json(p runspot_private.board_posts,viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'board',p.board,'topic',p.topic,'region',p.region,'title',p.title,'body',p.body,
   'nickname',coalesce((select nickname from public.profiles where id=p.author_id),'닉네임 없음'),
   'is_mine',p.author_id=viewer,'race_date',p.race_date,'race_place',p.race_place,'race_url',p.race_url,
   'created_at',p.created_at,'updated_at',p.updated_at);
$$;
create function runspot_private.update_my_board_post(post_id uuid,expected_updated_at timestamptz,requested_topic text,
 requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=runspot_private.require_board_viewer(); item runspot_private.board_posts;
 title_value text:=btrim(requested_title); body_value text:=btrim(requested_body);
 place_value text:=nullif(btrim(requested_race_place),''); url_value text:=nullif(btrim(requested_race_url),'');
begin
 if not runspot_private.can_interact() then raise exception '이메일 인증과 닉네임 등록을 확인해 주세요.' using errcode='42501'; end if;
 select * into item from runspot_private.board_posts where id=post_id for update;
 if not found or item.author_id<>viewer then raise exception '본인 글만 수정할 수 있습니다.' using errcode='42501'; end if;
 if item.board='race' and runspot_private.staff_role() is null then
  raise exception '대회 공지 수정에는 관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
 end if;
 if item.board='race' then
  if requested_topic is not null or requested_race_date is null or place_value is null or length(place_value)>80
   or (url_value is not null and (length(url_value)>500 or url_value !~ '^https://[^[:space:]]+$')) then
   raise exception '대회 날짜·장소와 https 링크를 확인해 주세요.' using errcode='22023';
  end if;
 elsif requested_topic is null or requested_topic not in ('course','tip','food')
  or requested_race_date is not null or place_value is not null or url_value is not null then
  raise exception '말머리를 확인해 주세요.' using errcode='22023';
 end if;
 if title_value is null or length(title_value) not between 1 and 80 or body_value is null or length(body_value) not between 1 and 2000 then
  raise exception '제목은 1~80자, 내용은 1~2000자로 입력해 주세요.' using errcode='22023';
 end if;
 -- 같은 내용 재전송은 무해하게 처리하고 다른 수정이 끼어들었으면 덮어쓰지 않습니다.
 if item.title=title_value and item.body=body_value and item.topic is not distinct from requested_topic
  and item.race_date is not distinct from requested_race_date and item.race_place is not distinct from place_value
  and item.race_url is not distinct from url_value then return; end if;
 if expected_updated_at is null or item.updated_at<>expected_updated_at then
  raise exception '글이 변경되었습니다. 새로고침 후 다시 수정해 주세요.' using errcode='P0001';
 end if;
 update runspot_private.board_posts set title=title_value,body=body_value,topic=requested_topic,race_date=requested_race_date,
  race_place=place_value,race_url=url_value,updated_at=clock_timestamp() where id=post_id;
end;
$$;
create function public.update_my_board_post(post_id uuid,expected_updated_at timestamptz,requested_topic text,
 requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.update_my_board_post(post_id,expected_updated_at,requested_topic,requested_title,requested_body,
  requested_race_date,requested_race_place,requested_race_url);
$$;

-- 글이 삭제되어도 신고 당시 내용과 처리 이력은 운영 검토용으로 보존합니다.
create table runspot_private.board_reports(
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null,
 reporter_id uuid not null references auth.users(id) on delete cascade,
 author_id uuid references auth.users(id) on delete set null,
 snapshot jsonb not null,
 reason text not null check(length(reason) between 1 and 500),
 status text not null default 'open' check(status in ('open','dismissed','removed')),
 created_at timestamptz not null default now(),
 resolved_by uuid references auth.users(id) on delete set null,
 resolved_at timestamptz,
 resolution_note text,
 unique(post_id,reporter_id)
);
create index board_reports_open on runspot_private.board_reports(created_at,id) where status='open';
alter table runspot_private.board_reports enable row level security;
create policy board_reports_service on runspot_private.board_reports for all to service_role using(true) with check(true);
revoke all on runspot_private.board_reports from public,anon,authenticated;
grant all on runspot_private.board_reports to service_role;
create function runspot_private.report_board_post(post_id uuid,requested_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=runspot_private.require_board_viewer(); item runspot_private.board_posts; reason_value text:=btrim(requested_reason);
begin
 if not runspot_private.can_interact() then raise exception '이메일 인증과 닉네임 등록 후 신고할 수 있습니다.' using errcode='42501'; end if;
 if reason_value is null or length(reason_value) not between 1 and 500 then
  raise exception '신고 사유를 1~500자로 입력해 주세요.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:user:'||viewer::text,0));
 select * into item from runspot_private.board_posts p where p.id=post_id for share;
 if not found or not runspot_private.board_author_visible(item.author_id,viewer)
   or (item.board='local' and item.region is distinct from runspot_private.my_board_region()) then
  raise exception '조회할 수 없는 게시글입니다.' using errcode='42501'; end if;
 if item.author_id=viewer then raise exception '본인 글은 신고할 수 없습니다.' using errcode='22023'; end if;
 if exists(select 1 from runspot_private.board_reports r where r.post_id=report_board_post.post_id and r.reporter_id=viewer) then return; end if;
 if (select count(*) from runspot_private.board_reports where reporter_id=viewer and created_at>now()-interval '1 day')>=20 then
  raise exception '신고는 하루에 20개까지 접수할 수 있습니다.' using errcode='P0001'; end if;
 insert into runspot_private.board_reports(post_id,reporter_id,author_id,snapshot,reason)
 values(item.id,viewer,item.author_id,runspot_private.board_post_json(item,viewer),reason_value);
end;
$$;
create function public.report_board_post(post_id uuid,requested_reason text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.report_board_post(post_id,requested_reason);
$$;
create function runspot_private.board_report_cases()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if runspot_private.staff_role() is null then raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'title',r.snapshot->>'title','body',r.snapshot->>'body',
  'nickname',r.snapshot->>'nickname','reason',r.reason,'created_at',r.created_at,'is_mine',r.author_id=auth.uid()) order by r.created_at,r.id),'[]'::jsonb)
  from (select * from runspot_private.board_reports where status='open' order by created_at,id limit 100)r);
end;
$$;
create function public.board_report_cases()
returns jsonb language sql stable security invoker set search_path='' as $$ select runspot_private.board_report_cases(); $$;
create function runspot_private.resolve_board_report(report_id uuid,decision text,note text)
returns void language plpgsql security definer set search_path='' as $$
declare item runspot_private.board_reports; target_id uuid;
begin
 perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
 perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
 if runspot_private.staff_role() is null then raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if decision is null or decision not in ('dismissed','removed') or note is null or length(btrim(note)) not between 1 and 500 then
  raise exception '처리 사유를 1~500자로 입력해 주세요.' using errcode='22023'; end if;
 select post_id into target_id from runspot_private.board_reports where id=report_id;
 if not found then raise exception '신고를 찾을 수 없습니다.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||target_id::text,0));
 select * into strict item from runspot_private.board_reports where id=report_id for update;
 if item.author_id=auth.uid() then raise exception '본인 게시글의 신고는 처리할 수 없습니다.' using errcode='42501'; end if;
 if item.status=decision then return; end if;
 if item.status<>'open' then raise exception '이미 처리한 신고입니다.' using errcode='P0001'; end if;
 if decision='removed' then
  delete from runspot_private.board_posts where id=item.post_id;
  update runspot_private.board_reports set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
   where post_id=item.post_id and status='open';
 else
  update runspot_private.board_reports set status=decision,resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note) where id=report_id;
 end if;
 insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'board_report_'||decision,item.id);
end;
$$;
create function public.resolve_board_report(report_id uuid,decision text,note text)
returns void language sql security invoker set search_path='' as $$ select runspot_private.resolve_board_report(report_id,decision,note); $$;

revoke all on function public.set_my_run_hidden(uuid,boolean),runspot_private.set_my_run_hidden(uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_my_run_hidden(uuid,boolean),runspot_private.set_my_run_hidden(uuid,boolean) to authenticated;

revoke all on function public.can_access_management(),runspot_private.can_access_management() from public,anon,authenticated;
grant execute on function public.can_access_management(),runspot_private.can_access_management() to authenticated;

revoke all on function public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text),runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text) from public,anon,authenticated;
grant execute on function public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text),runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text) to authenticated;

revoke all on function public.report_board_post(uuid,text),runspot_private.report_board_post(uuid,text) from public,anon,authenticated;
grant execute on function public.report_board_post(uuid,text),runspot_private.report_board_post(uuid,text) to authenticated;

revoke all on function public.board_report_cases(),runspot_private.board_report_cases() from public,anon,authenticated;
grant execute on function public.board_report_cases(),runspot_private.board_report_cases() to authenticated;

revoke all on function public.resolve_board_report(uuid,text,text),runspot_private.resolve_board_report(uuid,text,text) from public,anon,authenticated;
grant execute on function public.resolve_board_report(uuid,text,text),runspot_private.resolve_board_report(uuid,text,text) to authenticated;

notify pgrst,'reload schema';
