-- 사진을 읽은 후 교체되더라도 서버가 발행한 버전과 원본 해시가 일치해야 신고할 수 있습니다.
-- 신고되지 않은 이전 사진의 바이트는 보관하지 않습니다.
create table runspot_private.avatar_versions (
  version uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  photo_hash bytea not null
);
alter table runspot_private.avatar_versions enable row level security;
revoke all on runspot_private.avatar_versions from public, anon, authenticated;
alter table runspot_private.profile_avatars add column version uuid not null default gen_random_uuid();
insert into runspot_private.avatar_versions select version,user_id,sha256(photo) from runspot_private.profile_avatars;

create function runspot_private.version_avatar() returns trigger
language plpgsql set search_path='' as $$
begin
  new.version := gen_random_uuid();
  return new;
end;
$$;
create trigger version_avatar before insert or update of photo on runspot_private.profile_avatars
for each row execute function runspot_private.version_avatar();
-- 충돌 갱신에서 실제로 저장된 버전만 기록합니다.
create function runspot_private.remember_avatar() returns trigger
language plpgsql set search_path='' as $$
begin
  insert into runspot_private.avatar_versions values(new.version,new.user_id,sha256(new.photo));
  return null;
end;
$$;
create trigger remember_avatar after insert or update of photo on runspot_private.profile_avatars
for each row execute function runspot_private.remember_avatar();
revoke all on function runspot_private.version_avatar(),runspot_private.remember_avatar() from public,anon,authenticated;

alter table runspot_private.moderation_cases drop constraint moderation_cases_kind_check;
alter table runspot_private.moderation_cases add constraint moderation_cases_kind_check
  check(kind in ('post','comment','chat','meetup','avatar'));
alter table runspot_private.moderation_cases add column avatar_version uuid;
create unique index moderation_avatar_reporter on runspot_private.moderation_cases(avatar_version,reporter_id)
  where avatar_version is not null;

create function runspot_private.reportable_avatar(target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if target = viewer or not runspot_private.board_author_visible(target,viewer) then return null; end if;
  return (select jsonb_build_object('version',version,'photo',encode(photo,'base64'))
          from runspot_private.profile_avatars where user_id=target);
end;
$$;
create function runspot_private.report_avatar(target uuid,version_id uuid,jpeg text,reason text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := auth.uid(); bytes bytea; category text := split_part(reason,E'\n',1);
begin
  if viewer is null or not runspot_private.can_interact() or target=viewer
      or not runspot_private.board_author_visible(target,viewer) then
    raise exception '신고할 수 없는 프로필입니다.' using errcode='42501';
  end if;
  if reason is null or length(reason)>500 or category not in ('욕설·비방','스팸·광고','음란·불법 콘텐츠','개인정보 노출','기타')
     or (category='기타' and substring(reason from length(category)+1) !~ '[^[:space:]]') then
    raise exception '신고 분류와 사유를 확인해 주세요.' using errcode='22023';
  end if;
  bytes := runspot_private.avatar_jpeg(jpeg,307200);
  if not exists(select 1 from runspot_private.avatar_versions v where v.version=version_id
                and v.owner_id=target and v.photo_hash=sha256(bytes)) then
    raise exception '확인할 수 없는 프로필 사진입니다.' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reporter:'||viewer::text,0));
  if exists(select 1 from runspot_private.moderation_cases where avatar_version=version_id and reporter_id=viewer) then return; end if;
  if (select count(*) from runspot_private.moderation_cases where reporter_id=viewer and created_at>now()-interval '1 day')>=20 then
    raise exception '하루 신고 한도에 도달했습니다.' using errcode='22023';
  end if;
  insert into runspot_private.moderation_cases(reporter_id,author_id,kind,avatar_version,evidence,photo,reason)
    values(viewer,target,'avatar',version_id,'{}',bytes,btrim(reason));
end;
$$;
create function public.reportable_avatar(target uuid) returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.reportable_avatar(target); $$;
create function public.report_avatar(target uuid,version_id uuid,jpeg text,reason text) returns void language sql security invoker set search_path=''
as $$ select runspot_private.report_avatar(target,version_id,jpeg,reason); $$;
revoke all on function public.reportable_avatar(uuid),public.report_avatar(uuid,uuid,text,text),
  runspot_private.reportable_avatar(uuid),runspot_private.report_avatar(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.reportable_avatar(uuid),public.report_avatar(uuid,uuid,text,text),
  runspot_private.reportable_avatar(uuid),runspot_private.report_avatar(uuid,uuid,text,text) to authenticated;

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
 elsif c.kind='avatar' and decision<>'dismissed' then
   -- 사진이 교체된 경우 새 사진은 지우지 않습니다.
   delete from runspot_private.profile_avatars where user_id=c.author_id and version=c.avatar_version;
   update runspot_private.moderation_cases set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
     where avatar_version=c.avatar_version and status='open' and id<>c.id;
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

notify pgrst,'reload schema';
