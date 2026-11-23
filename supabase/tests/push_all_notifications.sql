\set ON_ERROR_STOP on
begin;
create function pg_temp.check_push(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
-- 발송 대기 중인 알림을 모두 가져온 뒤 끝난 것으로 표시합니다.
create function pg_temp.claim_all() returns jsonb language plpgsql as $$
declare result jsonb; item jsonb;
begin
 result:=public.claim_push_deliveries();
 for item in select * from jsonb_array_elements(result) loop
  perform public.finish_push_delivery((item->>'job_id')::uuid,(item->>'device_id')::uuid,(item->>'lease')::uuid,'sent');
 end loop;
 return result;
end; $$;
grant execute on function pg_temp.claim_all() to service_role;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000951','push951@example.com',now()),
 ('00000000-0000-0000-0000-000000000952','push952@example.com',now());
update public.profiles set nickname=case id when '00000000-0000-0000-0000-000000000951' then '받는러너' else '보낸러너' end,visibility='public'
 where id in ('00000000-0000-0000-0000-000000000951','00000000-0000-0000-0000-000000000952');
insert into auth.sessions(id,user_id) values('00000000-0000-0000-0000-000000000961','00000000-0000-0000-0000-000000000951');
insert into runspot_private.push_devices(token,user_id,session_id,platform,registered_at)
 values(repeat('p',40),'00000000-0000-0000-0000-000000000951','00000000-0000-0000-0000-000000000961','android',now()-interval '1 minute');
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000951','00000000-0000-0000-0000-000000000952','00000000-0000-0000-0000-000000000952','accepted');

-- 친구 메시지: 제목은 보낸 사람 이름, 내용은 메시지입니다.
insert into runspot_private.friend_messages(sender_id,recipient_id,body,request_id)
 values('00000000-0000-0000-0000-000000000952','00000000-0000-0000-0000-000000000951','오늘 저녁에 같이 뛸래?',gen_random_uuid());
set local role service_role;
select pg_temp.claim_all() as c \gset
select pg_temp.check_push(jsonb_array_length(:'c'::jsonb)=1 and :'c'::jsonb->0->>'kind'='friend_message'
 and :'c'::jsonb->0->>'title'='보낸러너' and :'c'::jsonb->0->>'body'='오늘 저녁에 같이 뛸래?','메시지 알림에 이름과 내용');
reset role;

-- 내 글 좋아요도 휴대폰 알림으로 보냅니다.
insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,title,body)
 values('00000000-0000-0000-0000-000000000971','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'national','tip','한강 코스 추천','내용');
insert into runspot_private.board_likes(post_id,user_id) values('00000000-0000-0000-0000-000000000971','00000000-0000-0000-0000-000000000952');
set local role service_role;
select pg_temp.claim_all() as c \gset
select pg_temp.check_push(jsonb_array_length(:'c'::jsonb)=1 and :'c'::jsonb->0->>'kind'='board_like'
 and :'c'::jsonb->0->>'body'='보낸러너님이 내 글을 좋아해요: 한강 코스 추천','좋아요 알림');
reset role;

-- 항목을 끄면 그 종류만 보내지 않고, 내용 표시를 끄면 이름·내용을 숨깁니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000951',true);
select public.my_push_preferences(board_like=>false,show_preview=>false) as prefs \gset
select pg_temp.check_push((:'prefs'::jsonb->>'board_like')='false' and (:'prefs'::jsonb->>'friend_message')='true'
 and (:'prefs'::jsonb->>'room_message')='true' and (:'prefs'::jsonb->>'crew_invite')='true','항목별 설정 저장');
reset role;
delete from runspot_private.board_likes;
delete from runspot_private.notifications;
insert into runspot_private.board_likes(post_id,user_id) values('00000000-0000-0000-0000-000000000971','00000000-0000-0000-0000-000000000952');
insert into runspot_private.friend_messages(sender_id,recipient_id,body,request_id)
 values('00000000-0000-0000-0000-000000000952','00000000-0000-0000-0000-000000000951','비밀 내용',gen_random_uuid());
set local role service_role;
select pg_temp.claim_all() as c \gset
select pg_temp.check_push(jsonb_array_length(:'c'::jsonb)=1 and :'c'::jsonb->0->>'kind'='friend_message'
 and :'c'::jsonb->0->>'title'='뜀터' and :'c'::jsonb->0->>'body'='새 메시지가 도착했어요.','끈 항목 제외·내용 숨김');
rollback;
