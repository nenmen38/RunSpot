create table runspot_private.meetups(
 id uuid primary key,
 host_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(length(btrim(title)) between 1 and 80),
 region text not null check(length(btrim(region)) between 1 and 40),
 place text not null check(length(btrim(place)) between 1 and 150),
 starts_at timestamptz not null,
 distance_km integer not null check(distance_km between 1 and 100),
 pace_seconds integer not null check(pace_seconds between 180 and 900),
 capacity integer not null check(capacity between 2 and 30),
 cancelled boolean not null default false,
 group_id uuid references runspot_private.running_groups(id) on delete set null,
 created_at timestamptz not null default now()
);
create index meetups_upcoming on runspot_private.meetups(starts_at,id) where not cancelled;
create index meetups_host on runspot_private.meetups(host_id,created_at);
create table runspot_private.meetup_members(
 meetup_id uuid references runspot_private.meetups(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(meetup_id,user_id)
);
create index meetup_members_user on runspot_private.meetup_members(user_id,meetup_id);
alter table runspot_private.meetups enable row level security;
alter table runspot_private.meetup_members enable row level security;
revoke all on runspot_private.meetups,runspot_private.meetup_members from public,anon,authenticated;

create function runspot_private.meetup_visible(host uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.can_interact() and runspot_private.is_active(host) and not exists(
   select 1 from runspot_private.blocks where (blocker_id=auth.uid() and blocked_id=host)
     or (blocked_id=auth.uid() and blocker_id=host));
$$;

create function runspot_private.meetup_list(region_filter text default '',pace_filter integer default null,only_mine boolean default false,page_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 if page_offset<0 or page_offset>10000 or length(region_filter)>40 then raise exception '검색 조건을 확인해 주세요.' using errcode='22023'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at,x.id),'[]') from (
 select m.id,m.title,m.region,m.place,m.starts_at,m.distance_km,m.pace_seconds,m.capacity,m.cancelled,m.group_id,
   p.nickname as host_name,m.host_id=auth.uid() as is_host,
   exists(select 1 from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=auth.uid()) as joined,
   (select count(*) from runspot_private.meetup_members u where u.meetup_id=m.id) as member_count
 from runspot_private.meetups m join public.profiles p on p.id=m.host_id
 where runspot_private.meetup_visible(m.host_id) and m.starts_at>now()-interval '6 hours'
   and (not m.cancelled or only_mine)
   and (coalesce(region_filter,'')='' or position(lower(region_filter) in lower(m.region))>0)
   and (pace_filter is null or abs(m.pace_seconds-pace_filter)<=30)
   and (not only_mine or exists(select 1 from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=auth.uid()))
 order by m.starts_at,m.id limit 30 offset page_offset
 )x);
end;
$$;

create function runspot_private.meetup_create(request_id uuid,title text,region text,place text,starts_at timestamptz,distance_km integer,pace_seconds integer,capacity integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); violation text;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('moderation:'||viewer::text,0));
 if exists(select 1 from runspot_private.moderation_actions a where a.user_id=viewer and a.kind<>'warning'
   and a.revoked_at is null and (a.expires_at is null or a.expires_at>now())) then raise exception '작성 제한 중에는 모임을 모집할 수 없습니다.' using errcode='42501'; end if;
 if exists(select 1 from runspot_private.meetups m where m.id=request_id and m.host_id=viewer
   and m.title=btrim(meetup_create.title) and m.region=btrim(meetup_create.region) and m.place=btrim(meetup_create.place)
   and m.starts_at=meetup_create.starts_at and m.distance_km=meetup_create.distance_km
   and m.pace_seconds=meetup_create.pace_seconds and m.capacity=meetup_create.capacity) then return request_id; end if;
 if starts_at is null or not isfinite(starts_at) or starts_at<now()+interval '5 minutes' or starts_at>now()+interval '90 days' then
   raise exception '출발은 5분 후부터 90일 이내로 설정해 주세요.' using errcode='22023'; end if;
 violation:=runspot_private.board_text_violation(title||' '||region||' '||place);
 if violation is not null then raise exception '모집 내용의 부적절한 표현이나 링크를 수정해 주세요.' using errcode='22023'; end if;
 if (select count(*) from runspot_private.meetups m where m.host_id=viewer and m.created_at>now()-interval '1 day')>=5 then
   raise exception '모집은 하루에 5개까지 등록할 수 있습니다.' using errcode='P0001'; end if;
 insert into runspot_private.meetups(id,host_id,title,region,place,starts_at,distance_km,pace_seconds,capacity)
 values(request_id,viewer,btrim(title),btrim(region),btrim(place),starts_at,distance_km,pace_seconds,capacity);
 insert into runspot_private.meetup_members(meetup_id,user_id) values(request_id,viewer);
 return request_id;
end;
$$;

create function runspot_private.meetup_action(meetup_id uuid,operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare m runspot_private.meetups; viewer uuid:=auth.uid(); created_group uuid;
begin
 select * into m from runspot_private.meetups where id=meetup_id for update;
 if not found or not runspot_private.meetup_visible(m.host_id) then raise exception '모임을 이용할 수 없습니다.' using errcode='42501'; end if;
 if operation='join' then
   if m.cancelled or m.starts_at<=now() or m.group_id is not null then raise exception '참가 접수가 끝났습니다.' using errcode='22023'; end if;
   if exists(select 1 from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=viewer) then return m.group_id; end if;
   if (select count(*) from runspot_private.meetup_members u where u.meetup_id=m.id)>=m.capacity then raise exception '정원이 찼습니다.' using errcode='22023'; end if;
   insert into runspot_private.meetup_members(meetup_id,user_id) values(m.id,viewer);
 elsif operation='leave' then
   if viewer=m.host_id then raise exception '주최자는 모임 취소를 이용해 주세요.' using errcode='22023'; end if;
   if m.group_id is not null then raise exception '출발 준비 후에는 함께 달리기 화면에서 나가 주세요.' using errcode='22023'; end if;
   delete from runspot_private.meetup_members u where u.meetup_id=m.id and u.user_id=viewer;
 elsif operation='cancel' then
   if viewer<>m.host_id then raise exception '주최자만 취소할 수 있습니다.' using errcode='42501'; end if;
   if m.group_id is not null then raise exception '출발 준비 후에는 함께 달리기 화면에서 취소해 주세요.' using errcode='22023'; end if;
   update runspot_private.meetups set cancelled=true where id=m.id;
 elsif operation='prepare' then
   if viewer<>m.host_id then raise exception '주최자만 출발을 준비할 수 있습니다.' using errcode='42501'; end if;
   if m.cancelled or m.starts_at>now()+interval '30 minutes' or m.starts_at<now()-interval '30 minutes' then
     raise exception '출발 전후 30분 안에 준비할 수 있습니다.' using errcode='22023'; end if;
   if m.group_id is not null then return m.group_id; end if;
   insert into runspot_private.running_groups(host_id) values(viewer) returning id into created_group;
   insert into runspot_private.running_group_members(group_id,user_id,status)
   select created_group,u.user_id,'accepted' from runspot_private.meetup_members u
   where u.meetup_id=m.id and runspot_private.is_active(u.user_id)
   and not exists(select 1 from runspot_private.blocks b where
     (b.blocker_id=u.user_id and b.blocked_id=viewer) or (b.blocked_id=u.user_id and b.blocker_id=viewer));
   update runspot_private.meetups set group_id=created_group where id=m.id;
   return created_group;
 else raise exception '지원하지 않는 모임 작업입니다.' using errcode='22023';
 end if;
 return m.group_id;
end;
$$;

create function public.meetup_list(region_filter text default '',pace_filter integer default null,only_mine boolean default false,page_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$
 select runspot_private.meetup_list(region_filter,pace_filter,only_mine,page_offset);
$$;
revoke all on function public.meetup_list(text,integer,boolean,integer),runspot_private.meetup_list(text,integer,boolean,integer) from public,anon,authenticated;
grant execute on function public.meetup_list(text,integer,boolean,integer),runspot_private.meetup_list(text,integer,boolean,integer) to authenticated;

create function public.meetup_create(request_id uuid,title text,region text,place text,starts_at timestamptz,distance_km integer,pace_seconds integer,capacity integer) returns uuid language sql security invoker set search_path='' as $$
 select runspot_private.meetup_create(request_id,title,region,place,starts_at,distance_km,pace_seconds,capacity);
$$;
revoke all on function public.meetup_create(uuid,text,text,text,timestamptz,integer,integer,integer),runspot_private.meetup_create(uuid,text,text,text,timestamptz,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.meetup_create(uuid,text,text,text,timestamptz,integer,integer,integer),runspot_private.meetup_create(uuid,text,text,text,timestamptz,integer,integer,integer) to authenticated;

create function public.meetup_action(meetup_id uuid,operation text) returns uuid language sql security invoker set search_path='' as $$
 select runspot_private.meetup_action(meetup_id,operation);
$$;
revoke all on function public.meetup_action(uuid,text),runspot_private.meetup_action(uuid,text) from public,anon,authenticated;
grant execute on function public.meetup_action(uuid,text),runspot_private.meetup_action(uuid,text) to authenticated;
revoke all on function runspot_private.meetup_visible(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';

-- 모집 글도 같은 관리자 검토와 제재 이력을 사용합니다.
alter table runspot_private.moderation_cases drop constraint moderation_cases_kind_check;
alter table runspot_private.moderation_cases add constraint moderation_cases_kind_check check(kind in ('post','comment','chat','meetup'));
alter table runspot_private.moderation_cases add column meetup_id uuid references runspot_private.meetups(id) on delete set null;
create unique index moderation_cases_meetup_reporter on runspot_private.moderation_cases(meetup_id,reporter_id);
create function runspot_private.report_meetup(meetup_id uuid,reason text)
returns void language plpgsql security definer set search_path='' as $$
declare m runspot_private.meetups; viewer uuid:=auth.uid();
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('reporter:'||viewer::text,0));
 select * into m from runspot_private.meetups where id=meetup_id;
 if not found or m.host_id=viewer or not runspot_private.meetup_visible(m.host_id) then raise exception '신고할 모임을 확인해 주세요.' using errcode='42501'; end if;
 if reason is null or length(btrim(reason)) not between 1 and 500 then raise exception '신고 사유를 입력해 주세요.' using errcode='22023'; end if;
 if exists(select 1 from runspot_private.moderation_cases c where c.meetup_id=m.id and c.reporter_id=viewer) then return; end if;
 if (select count(*) from runspot_private.moderation_cases c where c.reporter_id=viewer and c.created_at>now()-interval '1 day')>=20 then raise exception '하루 신고 한도에 도달했습니다.' using errcode='22023'; end if;
 insert into runspot_private.moderation_cases(meetup_id,reporter_id,author_id,kind,evidence,reason)
 values(m.id,viewer,m.host_id,'meetup',jsonb_build_object('title',m.title,'body',m.region||' · '||m.place||' · '||m.starts_at::text),btrim(reason));
end;
$$;
create function public.report_meetup(meetup_id uuid,reason text) returns void language sql security invoker set search_path='' as $$ select runspot_private.report_meetup(meetup_id,reason); $$;
revoke all on function public.report_meetup(uuid,text),runspot_private.report_meetup(uuid,text) from public,anon,authenticated;
grant execute on function public.report_meetup(uuid,text),runspot_private.report_meetup(uuid,text) to authenticated;
create or replace function runspot_private.moderation_decide(case_id bigint,decision text,note text)
returns void language plpgsql security definer set search_path='' as $$
declare c runspot_private.moderation_cases; report_target uuid;
begin
 perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
 perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
 if runspot_private.staff_role() is null then raise exception '관리자 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if decision is null or decision not in ('dismissed','warning','day','week','indefinite')
   or note is null or length(btrim(note)) not between 1 and 500 then raise exception '조치와 사유를 확인해 주세요.' using errcode='22023'; end if;
 -- 게시판 처리 함수의 잠금 순서와 맞춰 기존 신고 화면과의 교착을 방지합니다.
 select r.post_id into report_target from runspot_private.moderation_cases report_case
 join runspot_private.board_reports r on r.id=report_case.board_report_id where report_case.id=case_id;
 if report_target is not null then perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||report_target::text,0)); end if;
 select * into c from runspot_private.moderation_cases where id=case_id for update;
 if not found or c.author_id is null or c.author_id=auth.uid() or c.reporter_id=auth.uid() then
   raise exception '본인과 관련된 신고는 다른 관리자가 처리해야 합니다.' using errcode='42501'; end if;
 if c.status<>'open' then raise exception '이미 처리된 신고입니다.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('moderation:'||c.author_id::text,0));
 if decision<>'dismissed' then
   insert into runspot_private.moderation_actions(case_id,user_id,actor_id,kind,reason,expires_at)
   values(c.id,c.author_id,auth.uid(),decision,btrim(note),
     case decision when 'day' then now()+interval '24 hours' when 'week' then now()+interval '7 days' else null end);
 end if;
 if c.board_report_id is not null then
   perform runspot_private.resolve_board_report(c.board_report_id,case when decision='dismissed' then 'dismissed' else 'removed' end,note);
 elsif c.meetup_id is not null and decision<>'dismissed' then
   update runspot_private.meetups set cancelled=true where id=c.meetup_id;
   update runspot_private.running_groups set state='cancelled' where id=(select group_id from runspot_private.meetups where id=c.meetup_id) and state in ('lobby','scheduled');
   update runspot_private.moderation_cases set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
     where meetup_id=c.meetup_id and status='open' and id<>c.id;
 elsif decision<>'dismissed' then
   update runspot_private.friend_messages set kind='deleted',body='삭제된 메시지입니다.',photo=null,run_summary=null,reply_id=null
     where id=c.message_id and kind<>'deleted';
   -- 동일 메시지에 대한 중복 제재를 방지합니다.
   update runspot_private.moderation_cases set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
     where message_id=c.message_id and status='open' and id<>c.id;
 end if;
 update runspot_private.moderation_cases set status=case when decision='dismissed' then 'dismissed' else 'actioned' end,
   resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note) where id=c.id;
 insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'moderation_'||decision,c.author_id);
end;
$$;
