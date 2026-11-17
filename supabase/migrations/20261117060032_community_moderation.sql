-- 게시판·채팅 신고를 한 목록에서 검토하고 확정된 위반만 제재 이력에 기록합니다.
create table runspot_private.moderation_cases (
 id bigint generated always as identity primary key,
 board_report_id uuid unique references runspot_private.board_reports(id) on delete set null,
 message_id bigint,
 reporter_id uuid references auth.users(id) on delete set null,
 author_id uuid references auth.users(id) on delete set null,
 kind text not null check(kind in ('post','comment','chat')),
 evidence jsonb not null,
 photo bytea,
 reason text not null,
 status text not null default 'open' check(status in ('open','dismissed','removed','actioned')),
 created_at timestamptz not null default now(),
 resolved_by uuid references auth.users(id) on delete set null,
 resolved_at timestamptz,
 resolution_note text,
 unique(message_id,reporter_id)
);
create index moderation_cases_queue on runspot_private.moderation_cases(id desc) where status='open';
create index moderation_cases_author on runspot_private.moderation_cases(author_id,id desc);
create index moderation_cases_reporter on runspot_private.moderation_cases(reporter_id,created_at);
create table runspot_private.moderation_actions (
 id bigint generated always as identity primary key,
 case_id bigint not null unique references runspot_private.moderation_cases(id),
 user_id uuid references auth.users(id) on delete set null,
 actor_id uuid references auth.users(id) on delete set null,
 kind text not null check(kind in ('warning','day','week','indefinite')),
 reason text not null check(length(btrim(reason)) between 1 and 500),
 created_at timestamptz not null default now(),
 expires_at timestamptz,
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id) on delete set null,
 appeal text check(length(btrim(appeal)) between 1 and 1000),
 appealed_at timestamptz,
 appeal_status text check(appeal_status in ('pending','accepted','rejected')),
 appeal_note text,
 appeal_resolved_by uuid references auth.users(id) on delete set null,
 appeal_resolved_at timestamptz
);
create index moderation_actions_user on runspot_private.moderation_actions(user_id,id desc);
create index moderation_actions_appeals on runspot_private.moderation_actions(id desc) where appeal_status='pending';
alter table runspot_private.moderation_cases enable row level security;
alter table runspot_private.moderation_actions enable row level security;
revoke all on runspot_private.moderation_cases,runspot_private.moderation_actions from public,anon,authenticated;

-- 기존 신고 처리와도 상태를 동기화합니다.
create function runspot_private.sync_board_moderation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into runspot_private.moderation_cases(board_report_id,reporter_id,author_id,kind,evidence,reason,status,created_at,resolved_by,resolved_at,resolution_note)
 values(new.id,new.reporter_id,new.author_id,case when new.comment_id is null then 'post' else 'comment' end,
 new.snapshot,new.reason,new.status,new.created_at,new.resolved_by,new.resolved_at,new.resolution_note)
 on conflict(board_report_id) do update set status=excluded.status,resolved_by=excluded.resolved_by,
 resolved_at=excluded.resolved_at,resolution_note=excluded.resolution_note;
 return null;
end;
$$;
create trigger board_reports_moderation after insert or update of status on runspot_private.board_reports
for each row execute function runspot_private.sync_board_moderation();
insert into runspot_private.moderation_cases(board_report_id,reporter_id,author_id,kind,evidence,reason,status,created_at,resolved_by,resolved_at,resolution_note)
select id,reporter_id,author_id,case when comment_id is null then 'post' else 'comment' end,snapshot,reason,status,created_at,resolved_by,resolved_at,resolution_note
from runspot_private.board_reports;

-- 작성과 제재 처리를 같은 사용자 잠금으로 직렬화합니다. 기한이 지나면 다음 요청부터 자동 허용됩니다.
create function runspot_private.check_moderation_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare writer uuid;
begin
 if tg_table_name='friend_messages' then writer:=new.sender_id; else writer:=new.author_id; end if;
 perform pg_advisory_xact_lock(hashtextextended('moderation:'||writer::text,0));
 if exists(select 1 from runspot_private.moderation_actions a where a.user_id=writer
   and a.kind<>'warning' and a.revoked_at is null and (a.expires_at is null or a.expires_at>clock_timestamp())) then
   raise exception '커뮤니티 작성이 제한되어 있습니다. 설정의 이용 제한·이의신청에서 사유와 해제 시각을 확인해 주세요.' using errcode='42501';
 end if;
 return new;
end;
$$;
create trigger moderation_chat before insert on runspot_private.friend_messages
for each row execute function runspot_private.check_moderation_write();
create trigger moderation_posts before insert or update of title,body on runspot_private.board_posts
for each row execute function runspot_private.check_moderation_write();
create trigger moderation_comments before insert or update of body on runspot_private.board_comments
for each row execute function runspot_private.check_moderation_write();

create function runspot_private.report_chat(message_id bigint,reason text)
returns void language plpgsql security definer set search_path='' as $$
declare m runspot_private.friend_messages; viewer uuid:=auth.uid(); context_rows jsonb;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 if reason is null or length(btrim(reason)) not between 1 and 500 then raise exception '신고 사유를 1~500자로 입력해 주세요.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('chat_report:'||viewer::text,0));
 select * into m from runspot_private.friend_messages where id=message_id for share;
 if not found or m.recipient_id<>viewer then raise exception '받은 메시지만 신고할 수 있습니다.' using errcode='42501'; end if;
 if exists(select 1 from runspot_private.moderation_cases c where c.message_id=m.id and c.reporter_id=viewer) then return; end if;
 if m.kind='deleted' then raise exception '이미 삭제된 메시지입니다.' using errcode='22023'; end if;
 if (select count(*) from runspot_private.moderation_cases c where c.reporter_id=viewer and c.created_at>now()-interval '1 day')>=20 then
   raise exception '신고는 하루에 20개까지 접수할 수 있습니다.' using errcode='P0001'; end if;
 -- 신고 대상과 직전 세 메시지의 텍스트 요약만 증거로 보존합니다.
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into context_rows from (
   select id,sender_id,body,kind,sent_at from runspot_private.friend_messages
   where user_low=m.user_low and user_high=m.user_high and id<m.id order by id desc limit 3
 ) x;
 insert into runspot_private.moderation_cases(message_id,reporter_id,author_id,kind,evidence,photo,reason)
 values(m.id,viewer,m.sender_id,'chat',jsonb_build_object('body',m.body,'kind',m.kind,
   'run_summary',m.run_summary-'source_id','context',context_rows),m.photo,btrim(reason));
end;
$$;

create function runspot_private.moderation_list(mode text,target_id uuid default null,before_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 if mode<>'mine' and runspot_private.staff_role() is null then raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if mode='cases' then
   return (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]') from (
     select c.id,c.kind,c.author_id,p.nickname,c.evidence,c.reason,c.created_at,c.photo is not null as has_photo,
       c.author_id=auth.uid() or c.reporter_id=auth.uid() as conflict
     from runspot_private.moderation_cases c left join public.profiles p on p.id=c.author_id
     where c.status='open' and (before_id is null or c.id<before_id) order by c.id desc limit 50
   )x);
 elsif mode in ('mine','history','appeals') then
   return (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]') from (
     select a.id,a.user_id,p.nickname,a.kind,a.reason,a.created_at,a.expires_at,a.revoked_at,
       a.appeal,a.appeal_status,a.appeal_note,
       a.revoked_at is null and a.kind<>'warning' and (a.expires_at is null or a.expires_at>now()) as active,
       a.user_id=auth.uid() as conflict
     from runspot_private.moderation_actions a left join public.profiles p on p.id=a.user_id
     where (case mode when 'mine' then a.user_id=auth.uid() when 'history' then (target_id is null or a.user_id=target_id)
       else a.appeal_status='pending' end)
     and (before_id is null or a.id<before_id) order by a.id desc limit 50
   )x);
 end if;
 raise exception '조회 종류를 확인해 주세요.' using errcode='22023';
end;
$$;

create function runspot_private.moderation_photo(case_id bigint)
returns text language plpgsql stable security definer set search_path='' as $$
begin
 if runspot_private.staff_role() is null then raise exception '관리자 다중 인증이 필요합니다.' using errcode='42501'; end if;
 return (select encode(photo,'base64') from runspot_private.moderation_cases where id=case_id);
end;
$$;

create function runspot_private.moderation_decide(case_id bigint,decision text,note text)
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

create function runspot_private.moderation_appeal(action_id bigint,reason text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception '이의신청 사유를 1~1000자로 입력해 주세요.' using errcode='22023'; end if;
 update runspot_private.moderation_actions set appeal=btrim(moderation_appeal.reason),appealed_at=now(),appeal_status='pending'
 where id=action_id and user_id=auth.uid() and appeal is null and revoked_at is null;
 if not found then raise exception '이미 신청했거나 신청할 수 없는 조치입니다.' using errcode='22023'; end if;
end;
$$;

create function runspot_private.moderation_revoke(action_id bigint,accept boolean,note text)
returns void language plpgsql security definer set search_path='' as $$
declare a runspot_private.moderation_actions;
begin
 perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
 perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
 if runspot_private.staff_role() is null then raise exception '관리자 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if accept is null or note is null or length(btrim(note)) not between 1 and 500 then raise exception '처리 사유를 입력해 주세요.' using errcode='22023'; end if;
 select * into a from runspot_private.moderation_actions where id=action_id for update;
 if not found or a.user_id is null or a.user_id=auth.uid() then raise exception '처리 권한이 없습니다.' using errcode='42501'; end if;
 if a.revoked_at is not null or (not accept and a.appeal_status is distinct from 'pending') then
   raise exception '이미 처리되었거나 처리할 이의신청이 없습니다.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('moderation:'||a.user_id::text,0));
 update runspot_private.moderation_actions set
   revoked_at=case when accept then now() else null end,revoked_by=case when accept then auth.uid() else null end,
   appeal_status=case when a.appeal is null then null when accept then 'accepted' else 'rejected' end,
   appeal_note=btrim(note),appeal_resolved_by=auth.uid(),appeal_resolved_at=now() where id=a.id;
 insert into runspot_private.audit_logs(actor_id,action,target_id)
 values(auth.uid(),case when accept then 'moderation_revoked' else 'moderation_appeal_rejected' end,a.user_id);
end;
$$;

create function public.report_chat(message_id bigint,reason text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.report_chat(message_id,reason);
$$;
revoke all on function public.report_chat(bigint,text),runspot_private.report_chat(bigint,text) from public,anon,authenticated;
grant execute on function public.report_chat(bigint,text),runspot_private.report_chat(bigint,text) to authenticated;

create function public.moderation_list(mode text,target_id uuid default null,before_id bigint default null)
returns jsonb language sql security invoker set search_path='' as $$
 select runspot_private.moderation_list(mode,target_id,before_id);
$$;
revoke all on function public.moderation_list(text,uuid,bigint),runspot_private.moderation_list(text,uuid,bigint) from public,anon,authenticated;
grant execute on function public.moderation_list(text,uuid,bigint),runspot_private.moderation_list(text,uuid,bigint) to authenticated;

create function public.moderation_photo(case_id bigint)
returns text language sql security invoker set search_path='' as $$
 select runspot_private.moderation_photo(case_id);
$$;
revoke all on function public.moderation_photo(bigint),runspot_private.moderation_photo(bigint) from public,anon,authenticated;
grant execute on function public.moderation_photo(bigint),runspot_private.moderation_photo(bigint) to authenticated;

create function public.moderation_decide(case_id bigint,decision text,note text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.moderation_decide(case_id,decision,note);
$$;
revoke all on function public.moderation_decide(bigint,text,text),runspot_private.moderation_decide(bigint,text,text) from public,anon,authenticated;
grant execute on function public.moderation_decide(bigint,text,text),runspot_private.moderation_decide(bigint,text,text) to authenticated;

create function public.moderation_appeal(action_id bigint,reason text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.moderation_appeal(action_id,reason);
$$;
revoke all on function public.moderation_appeal(bigint,text),runspot_private.moderation_appeal(bigint,text) from public,anon,authenticated;
grant execute on function public.moderation_appeal(bigint,text),runspot_private.moderation_appeal(bigint,text) to authenticated;

create function public.moderation_revoke(action_id bigint,accept boolean,note text)
returns void language sql security invoker set search_path='' as $$
 select runspot_private.moderation_revoke(action_id,accept,note);
$$;
revoke all on function public.moderation_revoke(bigint,boolean,text),runspot_private.moderation_revoke(bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.moderation_revoke(bigint,boolean,text),runspot_private.moderation_revoke(bigint,boolean,text) to authenticated;
revoke all on function runspot_private.sync_board_moderation(),runspot_private.check_moderation_write() from public,anon,authenticated;
notify pgrst,'reload schema';
