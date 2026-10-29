-- 신고 원문과 처리 이력을 유지한 채 댓글·답글 신고를 같은 관리 목록에 연결합니다.
alter table runspot_private.board_reports add column comment_id uuid;
alter table runspot_private.board_reports drop constraint board_reports_post_id_reporter_id_key;
create unique index board_reports_post_reporter on runspot_private.board_reports(post_id,reporter_id) where comment_id is null;
create unique index board_reports_comment_reporter on runspot_private.board_reports(comment_id,reporter_id) where comment_id is not null;
create index board_reports_reporter_recent on runspot_private.board_reports(reporter_id,created_at desc);
create index if not exists board_comments_author_recent on runspot_private.board_comments(author_id,created_at desc);

-- 호환 문자·보이지 않는 문자만 정규화합니다. 짧은 초성이나 모호한 단어는 자동 제재하지 않습니다.
create function runspot_private.board_safety_text(value text)
returns text language sql immutable set search_path='' as $$
 select lower(translate(normalize(coalesce(value,''),NFKC),chr(8203)||chr(8204)||chr(8205)||chr(65279),''));
$$;
create function runspot_private.board_text_violation(value text)
returns text language plpgsql immutable set search_path='' as $$
declare clean text:=runspot_private.board_safety_text(value); compact text;
begin
 compact:=regexp_replace(clean,'[[:space:][:punct:][:digit:]]','','g');
 -- 시발점·시발역 등 정상 단어를 부분 일치로 막지 않습니다.
 compact:=replace(replace(compact,'시발점',''),'시발역','');
 if compact ~ '(씨발|씨팔|시발|개새끼|개색끼|씹새끼|좆같|좆나|지랄)' or
    clean ~ '(^|[^가-힣])병[[:space:][:punct:][:digit:]]{0,4}신(아|같|새끼|들|$|[^가-힣])' or
    clean ~ '\m(fuck|fucking|motherfucker)\M' then return 'profanity'; end if;
 if (select count(*) from regexp_matches(clean,'https?://','g'))>5 then return 'link_spam'; end if;
 return null;
end;
$$;

-- 앱을 우회한 직접 RPC와 관리자 작성도 같은 검사 규칙을 적용합니다.
create function runspot_private.check_board_safety()
returns trigger language plpgsql security definer set search_path='' as $$
declare violation text; duplicate boolean:=false; fingerprint text;
begin
 if tg_table_name='board_posts' then
  if tg_op='UPDATE' and new.title is not distinct from old.title and new.body is not distinct from old.body then return new; end if;
  violation:=coalesce(runspot_private.board_text_violation(new.title),runspot_private.board_text_violation(new.body));
  if violation is distinct from 'profanity' and (select count(*) from regexp_matches(
    runspot_private.board_safety_text(new.title||chr(10)||new.body),'https?://','g'))>5 then violation:='link_spam'; end if;
 else
  if tg_op='UPDATE' and new.body is not distinct from old.body then return new; end if;
  violation:=runspot_private.board_text_violation(new.body);
 end if;
 if violation='profanity' then
  raise exception '욕설·비방 표현을 수정한 뒤 다시 등록해 주세요.' using errcode='22023';
 elsif violation='link_spam' then
  raise exception '링크는 한 글에 5개까지 첨부할 수 있습니다.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('board_safety:'||new.author_id::text,0));
 fingerprint:=regexp_replace(runspot_private.board_safety_text(new.body),'[[:space:]]+',' ','g');
 -- 짧은 인사·응원은 허용하고, 20자 이상 본문의 반복 등록만 하루 동안 차단합니다.
 if length(btrim(fingerprint))>=20 then
  if tg_table_name='board_posts' then
   select exists(select 1 from runspot_private.board_posts p where p.author_id=new.author_id and p.id<>new.id
    and p.created_at>now()-interval '1 day'
    and regexp_replace(runspot_private.board_safety_text(p.body),'[[:space:]]+',' ','g')=fingerprint) into duplicate;
  else
   select exists(select 1 from runspot_private.board_comments c where c.author_id=new.author_id and c.id<>new.id
    and c.created_at>now()-interval '1 day'
    and regexp_replace(runspot_private.board_safety_text(c.body),'[[:space:]]+',' ','g')=fingerprint) into duplicate;
  end if;
 end if;
 if duplicate then raise exception '같은 내용을 반복해서 등록할 수 없습니다.' using errcode='22023'; end if;
 return new;
end;
$$;
create trigger board_posts_safety before insert or update of title,body on runspot_private.board_posts
 for each row execute function runspot_private.check_board_safety();
create trigger board_comments_safety before insert or update of body on runspot_private.board_comments
 for each row execute function runspot_private.check_board_safety();
revoke all on function runspot_private.board_safety_text(text),runspot_private.board_text_violation(text),runspot_private.check_board_safety()
 from public,anon,authenticated;

create function runspot_private.report_board_comment(comment_id uuid,requested_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=runspot_private.require_board_viewer(); item runspot_private.board_comments;
 post runspot_private.board_posts; reason_value text:=btrim(requested_reason);
begin
 if not runspot_private.can_interact() then raise exception '이메일 인증과 닉네임 등록 후 신고할 수 있습니다.' using errcode='42501'; end if;
 if reason_value is null or length(reason_value) not between 1 and 500 then
  raise exception '신고 사유를 1~500자로 입력해 주세요.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:user:'||viewer::text,0));
 select * into item from runspot_private.board_comments c where c.id=comment_id;
 if not found then raise exception '조회할 수 없는 댓글입니다.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||item.post_id::text,0));
 select * into post from runspot_private.board_posts p where p.id=item.post_id for share;
 perform runspot_private.require_visible_board_post(item.post_id,viewer);
 select * into item from runspot_private.board_comments c where c.id=comment_id for share;
 if not found or not runspot_private.board_author_visible(item.author_id,viewer)
  or (item.parent_id is not null and not exists(select 1 from runspot_private.board_comments parent
    where parent.id=item.parent_id and runspot_private.board_author_visible(parent.author_id,viewer))) then
  raise exception '조회할 수 없는 댓글입니다.' using errcode='42501'; end if;
 if item.author_id=viewer then raise exception '본인 댓글은 신고할 수 없습니다.' using errcode='22023'; end if;
 if exists(select 1 from runspot_private.board_reports r where r.comment_id=report_board_comment.comment_id and r.reporter_id=viewer) then return; end if;
 if (select count(*) from runspot_private.board_reports where reporter_id=viewer and created_at>now()-interval '1 day')>=20 then
  raise exception '신고는 하루에 20개까지 접수할 수 있습니다.' using errcode='P0001'; end if;
 insert into runspot_private.board_reports(post_id,comment_id,reporter_id,author_id,snapshot,reason)
 values(item.post_id,item.id,viewer,item.author_id,jsonb_build_object('title',post.title,'body',item.body,
  'nickname',coalesce((select nickname from public.profiles where id=item.author_id),'닉네임 없음'),
  'parent_id',item.parent_id,'created_at',item.created_at),reason_value);
end;
$$;
create function public.report_board_comment(comment_id uuid,requested_reason text)
returns void language sql security invoker set search_path='' as $$ select runspot_private.report_board_comment(comment_id,requested_reason); $$;
revoke all on function runspot_private.report_board_comment(uuid,text),public.report_board_comment(uuid,text) from public,anon,authenticated;
grant execute on function runspot_private.report_board_comment(uuid,text),public.report_board_comment(uuid,text) to authenticated;

create or replace function runspot_private.report_board_post(post_id uuid,requested_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=runspot_private.require_board_viewer(); item runspot_private.board_posts; reason_value text:=btrim(requested_reason);
begin
 if not runspot_private.can_interact() then raise exception '이메일 인증과 닉네임 등록 후 신고할 수 있습니다.' using errcode='42501'; end if;
 if reason_value is null or length(reason_value) not between 1 and 500 then
  raise exception '신고 사유를 1~500자로 입력해 주세요.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('board_reports:user:'||viewer::text,0));
 perform pg_advisory_xact_lock(hashtextextended('board_reports:post:'||post_id::text,0));
 select * into item from runspot_private.board_posts p where p.id=post_id for share;
 if not found or not runspot_private.board_author_visible(item.author_id,viewer)
   or (item.board='local' and item.region is distinct from runspot_private.my_board_region()) then
  raise exception '조회할 수 없는 게시글입니다.' using errcode='42501'; end if;
 if item.author_id=viewer then raise exception '본인 글은 신고할 수 없습니다.' using errcode='22023'; end if;
 if exists(select 1 from runspot_private.board_reports r where r.post_id=report_board_post.post_id and r.comment_id is null and r.reporter_id=viewer) then return; end if;
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
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'kind',case when r.comment_id is null then 'post' else 'comment' end,'title',r.snapshot->>'title','body',r.snapshot->>'body',
  'nickname',r.snapshot->>'nickname','reason',r.reason,'created_at',r.created_at,'is_mine',r.author_id=auth.uid()) order by r.created_at,r.id),'[]'::jsonb)
  from (select * from runspot_private.board_reports where status='open' order by created_at,id limit 100)r);
end;
$$;

create or replace function runspot_private.resolve_board_report(report_id uuid,decision text,note text)
returns void language plpgsql security definer set search_path='' as $$
declare item runspot_private.board_reports; target_id uuid; removed_comments uuid[];
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
  update runspot_private.board_reports set status=decision,resolved_by=auth.uid(),resolved_at=now(),resolution_note=btrim(note) where id=report_id;
 end if;
 insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'board_report_'||decision,item.id);
end;
$$;

notify pgrst,'reload schema';
