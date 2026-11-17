\set ON_ERROR_STOP on
begin;
create function pg_temp.check_live(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000271','live271@example.com',now()),
 ('00000000-0000-0000-0000-000000000272','live272@example.com',now()),
 ('00000000-0000-0000-0000-000000000273','live273@example.com',now());
update public.profiles set nickname='실시간검증'||right(id::text,3),visibility='friends' where id::text like '%00000000027_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000271','00000000-0000-0000-0000-000000000272','00000000-0000-0000-0000-000000000271','accepted'),
 ('00000000-0000-0000-0000-000000000271','00000000-0000-0000-0000-000000000273','00000000-0000-0000-0000-000000000271','accepted');
insert into auth.sessions(id,user_id) values ('00000000-0000-0000-0000-000000000282','00000000-0000-0000-0000-000000000272');

set local role authenticated;
-- 272가 휴대폰을 등록해 두고, 271이 메시지 두 개와 273도 하나를 보냅니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000272',true);
select set_config('request.jwt.claims','{"session_id":"00000000-0000-0000-0000-000000000282"}',true);
select public.register_push_device(repeat('c',40),'android');
select pg_temp.check_live((public.my_push_preferences()->>'friend_message')::boolean,'메시지 알림 기본 켜짐');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000271',true);
select public.friend_chat_send('00000000-0000-0000-0000-000000000272','안녕','00000000-0000-0000-0000-000000000031');
select public.friend_chat_send('00000000-0000-0000-0000-000000000272','뛰자','00000000-0000-0000-0000-000000000032');
select pg_temp.check_live(public.friend_chat_unread_total()=0,'보낸 사람은 안 읽은 수 없음');

-- 실시간 신호는 내 주제(chat:내ID)에서만 받습니다.
select set_config('realtime.topic','chat:00000000-0000-0000-0000-000000000271',true);
select pg_temp.check_live((select count(*)>0 and bool_and(payload='{}'::jsonb) from realtime.messages),'내 주제 신호 수신·내용 없음');
select set_config('realtime.topic','chat:00000000-0000-0000-0000-000000000272',true);
select pg_temp.check_live((select count(*)=0 from realtime.messages),'남의 주제 신호 차단');
select pg_temp.check_live(pg_temp.fails('insert into realtime.messages(extension,payload) values(''broadcast'',''{}'')','42501'),'앱에서 신호 보내기 차단');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000272',true);
select pg_temp.check_live(public.friend_chat_unread_total()=2,'안 읽은 총 개수');

-- 휴대폰 알림은 메시지마다 만들고, 대상은 보낸 친구입니다.
reset role;
set local role service_role;
select public.claim_push_deliveries() as claimed \gset
select pg_temp.check_live((select count(*)=2 and bool_and(c->>'kind'='friend_message'
  and c->>'target_id'='00000000-0000-0000-0000-000000000271') from jsonb_array_elements(:'claimed'::jsonb) c),'메시지 알림 발송');
reset role;

-- 읽은 메시지는 다시 알리지 않습니다.
delete from runspot_private.push_deliveries;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000272',true);
select public.friend_chat_mark_read('00000000-0000-0000-0000-000000000271',9223372036854775807);
select pg_temp.check_live(public.friend_chat_unread_total()=0,'읽으면 0');
reset role;
set local role service_role;
select pg_temp.check_live(jsonb_array_length(public.claim_push_deliveries())=0,'읽은 메시지는 알리지 않음');
reset role;

-- 메시지 알림을 끄면 보내지 않습니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000272',true);
select public.my_push_preferences(friend_message=>false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000271',true);
select public.friend_chat_send('00000000-0000-0000-0000-000000000272','또 있어?','00000000-0000-0000-0000-000000000033');
reset role;
set local role service_role;
select pg_temp.check_live(jsonb_array_length(public.claim_push_deliveries())=0,'알림 끄면 발송 안 함');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000272',true);
select pg_temp.check_live(public.friend_chat_unread_total()=1,'알림을 꺼도 안 읽은 수는 셈');
reset role;
set local role anon;
select pg_temp.check_live(pg_temp.fails('select public.friend_chat_unread_total()','42501'),'익명 금지');
rollback;
