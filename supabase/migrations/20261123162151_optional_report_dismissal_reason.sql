-- 문제없음으로 신고를 종결할 때만 처리 사유를 생략할 수 있습니다.
create or replace function runspot_private.resolve_board_report(report_id uuid,decision text,note text)
returns void language plpgsql security definer set search_path='' as $$
declare item runspot_private.board_reports; target_id uuid; removed_comments uuid[];
begin
 perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
 perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
 if runspot_private.staff_role() is null then raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if decision is null or decision not in ('dismissed','removed')
   or coalesce(length(btrim(note)), 0) not between (case when decision='dismissed' then 0 else 1 end) and 500 then
  raise exception '처리 방법과 사유를 확인해 주세요.' using errcode='22023'; end if;
 select post_id into target_id from runspot_private.board_reports where id=report_id;
 if not found then raise exception '신고를 찾을 수 없습니다.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||target_id::text,0));
 select * into strict item from runspot_private.board_reports where id=report_id for update;
 if item.author_id=auth.uid() then raise exception '본인 콘텐츠의 신고는 처리할 수 없습니다.' using errcode='42501'; end if;
 if item.status=decision then return; end if;
 if item.status<>'open' then raise exception '이미 처리한 신고입니다.' using errcode='P0001'; end if;
 if decision='removed' and item.comment_id is not null then
  select array_agg(c.id) into removed_comments from runspot_private.board_comments c
    where c.id=item.comment_id or c.parent_id=item.comment_id;
  delete from runspot_private.board_comments where id=item.comment_id;
  update runspot_private.board_reports set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
   where status='open' and (comment_id=item.comment_id or comment_id=any(removed_comments));
 elsif decision='removed' then
  delete from runspot_private.board_posts where id=item.post_id;
  update runspot_private.board_reports set status='removed',resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note)
   where post_id=item.post_id and status='open';
 else
  update runspot_private.board_reports set status=decision,resolved_by=auth.uid(),resolved_at=now(),resolution_note=nullif(btrim(note), '') where id=report_id;
 end if;
 insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'board_report_'||decision,item.id);
end;
$$;

create or replace function runspot_private.moderation_decide(case_id bigint,decision text,note text)
returns void language plpgsql security definer set search_path='' as $$
declare c runspot_private.moderation_cases; report_target uuid;
begin
 perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
 perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
 if runspot_private.staff_role() is null then raise exception '관리자 다중 인증이 필요합니다.' using errcode='42501'; end if;
 if decision is null or decision not in ('dismissed','warning','day','week','indefinite')
   or coalesce(length(btrim(note)), 0) not between (case when decision='dismissed' then 0 else 1 end) and 500 then raise exception '조치와 사유를 확인해 주세요.' using errcode='22023'; end if;
 -- 게시판 처리 함수의 잠금 순서와 맞춰 기존 신고 화면과의 교착을 방지합니다.
 select r.post_id into report_target from runspot_private.moderation_cases report_case
 join runspot_private.board_reports r on r.id=report_case.board_report_id where report_case.id=case_id;
 if report_target is not null then perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||report_target::text,0)); end if;
 select * into c from runspot_private.moderation_cases where id=case_id for update;
 if not found or c.author_id is null or c.author_id=auth.uid() then
   raise exception '본인 계정이 신고된 건은 직접 처리할 수 없습니다.' using errcode='42501'; end if;
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
   resolved_by=auth.uid(),resolved_at=now(),resolution_note=nullif(btrim(note), '') where id=c.id;
 insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'moderation_'||decision,c.author_id);
end;
$$;
