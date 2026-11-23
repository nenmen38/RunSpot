\set ON_ERROR_STOP on
begin;
create function pg_temp.check_moderation(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=code; end; $$;
\set writer '00000000-0000-0000-0000-000000000381'
\set reader '00000000-0000-0000-0000-000000000382'
\set staff '00000000-0000-0000-0000-000000000383'
\set moderator '00000000-0000-0000-0000-000000000384'
insert into auth.users(id,email,email_confirmed_at) values
(:'writer','mod381@example.com',now()),(:'reader','mod382@example.com',now()),(:'staff','mod383@example.com',now()),(:'moderator','mod384@example.com',now());
update public.profiles set nickname='제재검증'||right(id::text,3) where id in (:'writer',:'reader',:'staff');
insert into runspot_private.user_roles(user_id,role) values(:'staff','admin'),(:'writer','admin'),(:'moderator','moderator');
insert into public.friendships(user_low,user_high,requested_by,status) values(:'writer',:'reader',:'writer','accepted');

set local role authenticated;
select set_config('request.jwt.claim.sub',:'writer',true);
select public.friend_chat_send(:'reader','신고할 메시지',gen_random_uuid());
select public.friend_chat_read(:'reader')->0->>'id' as message_id \gset
select pg_temp.check_moderation(pg_temp.fails(format('select public.report_chat(%s,%L)',:message_id,'본인 신고'),'42501'),'보낸 메시지 신고 금지');
select set_config('request.jwt.claim.sub',:'reader',true);
select public.report_chat(:message_id,'반복 괴롭힘');
select public.report_chat(:message_id,'재시도');
select pg_temp.check_moderation(pg_temp.fails('select public.moderation_list(''cases'')','42501'),'일반 사용자 관리 조회 금지');
reset role;
select id as case_id from runspot_private.moderation_cases where message_id=:message_id \gset
select pg_temp.check_moderation((select count(*)=1 from runspot_private.moderation_cases where message_id=:message_id),'중복 신고 방지');

set local role authenticated;
select set_config('request.jwt.claim.sub',:'staff',true);
select pg_temp.check_moderation(pg_temp.fails('select public.moderation_list(''cases'')','42501'),'관리자 다중 인증 필요');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.check_moderation(public.admin_pending_notification_count()=1,'관리자 홈 알림에 미처리 신고 표시');
select set_config('request.jwt.claim.sub',:'moderator',true);
select pg_temp.check_moderation(public.admin_pending_notification_count()=0,'운영 담당자에게 관리자 홈 알림 비공개');
select set_config('request.jwt.claim.sub',:'reader',true);
select pg_temp.check_moderation(public.admin_pending_notification_count()=0,'일반 사용자에게 관리자 홈 알림 비공개');
select set_config('request.jwt.claim.sub',:'staff',true);
select public.moderation_decide(:case_id,'day','상대방에게 반복적으로 괴롭히는 메시지를 보냄');
select pg_temp.check_moderation(pg_temp.fails(format('select public.moderation_decide(%s,''week'',''중복 처리'')',:case_id),'22023'),'중복 제재 차단');
select pg_temp.check_moderation(public.admin_pending_notification_count()=0,'처리한 신고는 홈 알림에서 제외');
select public.moderation_list('history',:'writer')->0->>'id' as action_id \gset

select set_config('request.jwt.claim.sub',:'writer',true);
select pg_temp.check_moderation(public.unread_notification_count()=1,'조치 대상자에게 읽지 않은 알림 한 건');
select pg_temp.check_moderation(
  public.my_notifications() @> '[{"kind":"moderation_action","moderation_kind":"day","moderation_reason":"상대방에게 반복적으로 괴롭히는 메시지를 보냄"}]'::jsonb
    and not (public.my_notifications()::text like '%반복 괴롭힘%'),
  '관리자 처리 사유만 알림에 표시');
select public.mark_notifications_read(now());
select pg_temp.check_moderation(public.unread_notification_count()=0,'조치 알림 읽음 처리');
select pg_temp.check_moderation((public.moderation_list('mine')->0->>'active')::boolean,'본인 활성 제재 조회');
select pg_temp.check_moderation(pg_temp.fails(format('select public.friend_chat_send(%L,''제재 중 전송'',gen_random_uuid())',:'reader'),'42501'),'제재 중 채팅 차단');
select pg_temp.check_moderation(pg_temp.fails('select public.create_board_post(gen_random_uuid(),''national'',''제재 중 글'',''작성 차단 확인'',''tip'')','42501'),'제재 중 게시글 차단');
select public.moderation_appeal(:action_id,'대화 맥락을 다시 확인해 주세요.');
select pg_temp.check_moderation(pg_temp.fails(format('select public.moderation_appeal(%s,''중복 신청'')',:action_id),'22023'),'이의신청 중복 차단');

select set_config('request.jwt.claim.sub',:'staff',true);
select pg_temp.check_moderation(jsonb_array_length(public.moderation_list('appeals'))=1,'이의신청 관리자 조회');
select pg_temp.check_moderation(public.admin_pending_notification_count()=1,'대기 중인 이의신청을 홈 알림에 표시');
select public.moderation_revoke(:action_id,true,'맥락 확인 후 조치를 취소함');
select set_config('request.jwt.claim.sub',:'writer',true);
select public.friend_chat_send(:'reader','취소 후 전송',gen_random_uuid());
select pg_temp.check_moderation(not (public.moderation_list('mine')->0->>'active')::boolean,'취소 즉시 복구');

-- 기한이 지난 제재는 별도 예약 작업 없이 작성을 허용합니다.
reset role;
update runspot_private.moderation_actions set revoked_at=null,revoked_by=null,expires_at=now()-interval '1 second' where id=:action_id;
set local role authenticated;
select set_config('request.jwt.claim.sub',:'writer',true);
select public.friend_chat_send(:'reader','기간 만료 후 전송',gen_random_uuid());
select pg_temp.check_moderation(not (public.moderation_list('mine')->0->>'active')::boolean,'기간 만료 자동 해제');
select set_config('request.jwt.claim.sub',:'reader',true);
select pg_temp.check_moderation(jsonb_array_length(public.moderation_list('mine'))=0,'타인의 제재 내역 비공개');
select pg_temp.check_moderation(jsonb_array_length(public.my_notifications())=0,'신고자에게 대상자의 조치 알림 비공개');
select pg_temp.check_moderation(pg_temp.fails(format('select public.moderation_revoke(%s,true,''권한 우회'')',:action_id),'42501'),'일반 사용자 해제 금지');

-- 게시판 신고도 통합 목록으로 연결하고 검토 결과를 기존 신고에 반영합니다.
reset role;
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body)
values(:'writer',gen_random_uuid(),'national','tip','검토 대상','운영 검토할 본문입니다.') returning id as post_id \gset
set local role authenticated;
select set_config('request.jwt.claim.sub',:'staff',true);
select public.report_board_post(:'post_id','게시글 신고');
reset role;
select c.id as board_case_id from runspot_private.moderation_cases c join runspot_private.board_reports r on r.id=c.board_report_id where r.post_id=:'post_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub',:'writer',true);
select pg_temp.check_moderation((public.moderation_list('cases')->0->>'conflict')::boolean,'신고 대상 관리자에게 처리 제한 표시');
select pg_temp.check_moderation(pg_temp.fails(format('select public.moderation_decide(%s,%L,%L)',:board_case_id,'dismissed','본인 신고 종결'),'42501'),'신고 대상 관리자 처리 금지');
select set_config('request.jwt.claim.sub',:'staff',true);
select pg_temp.check_moderation(not (public.moderation_list('cases')->0->>'conflict')::boolean,'신고를 접수한 관리자는 처리 가능');
select public.moderation_decide(:board_case_id,'warning','부적절한 글로 경고');
select set_config('request.jwt.claim.sub',:'writer',true);
select pg_temp.check_moderation(public.unread_notification_count()=1
  and public.my_notifications() @> '[{"kind":"moderation_action","moderation_kind":"warning","moderation_reason":"부적절한 글로 경고"}]'::jsonb,
  '게시글이 삭제되어도 경고 알림 표시');
select public.friend_chat_send(:'reader','문제없음 처리 대상',gen_random_uuid());
select public.friend_chat_read(:'reader')->0->>'id' as dismissed_message_id \gset
select set_config('request.jwt.claim.sub',:'reader',true);
select public.report_chat(:dismissed_message_id,'문제없음 검증');
select set_config('request.jwt.claim.sub',:'staff',true);
select public.moderation_list('cases')->0->>'id' as dismissed_case_id \gset
select public.moderation_decide(:dismissed_case_id,'dismissed','위반 내용 없음');
select set_config('request.jwt.claim.sub',:'writer',true);
select pg_temp.check_moderation(public.unread_notification_count()=1,'문제없음 처리 시 새 알림 없음');
reset role;
select pg_temp.check_moderation(not exists(select 1 from runspot_private.board_posts where id=:'post_id'),'확정 위반 게시글 삭제');
select pg_temp.check_moderation((select status='removed' from runspot_private.board_reports where post_id=:'post_id'),'기존 신고 상태 동기화');
set local role anon;
select pg_temp.check_moderation(pg_temp.fails('select public.moderation_list(''mine'')','42501'),'익명 조회 금지');
rollback;
