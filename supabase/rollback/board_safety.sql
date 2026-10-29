-- 먼저 앱의 댓글 신고 기능을 이전 버전으로 되돌린 뒤 실행합니다.
-- 접수된 댓글 신고가 있으면 증거 손실을 방지하기 위해 복구를 중단합니다.
begin;
do $$ begin
 if exists(select 1 from runspot_private.board_reports where comment_id is not null) then
  raise exception '댓글 신고 자료가 있어 자동 복구할 수 없습니다. 자료 보존 후 운영자가 확인해 주세요.';
 end if;
end; $$;
drop trigger board_posts_safety on runspot_private.board_posts;
drop trigger board_comments_safety on runspot_private.board_comments;
drop function runspot_private.check_board_safety();
drop function runspot_private.board_text_violation(text);
drop function runspot_private.board_safety_text(text);
drop function public.report_board_comment(uuid,text);
drop function runspot_private.report_board_comment(uuid,text);
create or replace function runspot_private.report_board_post(post_id uuid,requested_reason text)
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

create or replace function runspot_private.board_report_cases()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if runspot_private.staff_role() is null then raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'title',r.snapshot->>'title','body',r.snapshot->>'body',
  'nickname',r.snapshot->>'nickname','reason',r.reason,'created_at',r.created_at,'is_mine',r.author_id=auth.uid()) order by r.created_at,r.id),'[]'::jsonb)
  from (select * from runspot_private.board_reports where status='open' order by created_at,id limit 100)r);
end;
$$;

create or replace function runspot_private.resolve_board_report(report_id uuid,decision text,note text)
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

drop index runspot_private.board_reports_post_reporter;
drop index runspot_private.board_reports_comment_reporter;
drop index runspot_private.board_reports_reporter_recent;
alter table runspot_private.board_reports drop column comment_id;
alter table runspot_private.board_reports add constraint board_reports_post_id_reporter_id_key unique(post_id,reporter_id);
notify pgrst,'reload schema';
commit;
