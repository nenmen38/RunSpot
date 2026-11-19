\set ON_ERROR_STOP on
begin;
create function pg_temp.check_room(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000311','room311@example.com',now()),
 ('00000000-0000-0000-0000-000000000312','room312@example.com',now()),
 ('00000000-0000-0000-0000-000000000313','room313@example.com',now()),
 ('00000000-0000-0000-0000-000000000314','room314@example.com',now());
update public.profiles set nickname='단톡'||right(id::text,3),visibility='friends' where id::text like '%00000000031_';
-- 311-312 친구, 311-313은 같은 크루, 314는 아무 관계 없음
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000312','00000000-0000-0000-0000-000000000311','accepted');
insert into runspot_private.crews(owner_id,name,icon) values('00000000-0000-0000-0000-000000000311','단톡크루','wave');
select id as crew from runspot_private.crews where name='단톡크루' \gset
insert into runspot_private.crew_members(user_id,crew_id,role) values
 ('00000000-0000-0000-0000-000000000311',:'crew','owner'),('00000000-0000-0000-0000-000000000313',:'crew','member');
insert into auth.sessions(id,user_id) values ('00000000-0000-0000-0000-000000000322','00000000-0000-0000-0000-000000000312');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000312',true);
select set_config('request.jwt.claims','{"session_id":"00000000-0000-0000-0000-000000000322"}',true);
select public.register_push_device(repeat('r',40),'android');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000311',true);
select pg_temp.check_room(pg_temp.fails(
  'select public.create_chat_room(array[''00000000-0000-0000-0000-000000000314''::uuid])','42501'),'모르는 사람 초대 거부');
select pg_temp.check_room(pg_temp.fails('select public.create_chat_room(array[]::uuid[])','22023'),'빈 대화방 거부');
-- 친구(312)와 크루원(313)으로 단톡을 만듭니다.
select public.create_chat_room(array['00000000-0000-0000-0000-000000000312'::uuid,'00000000-0000-0000-0000-000000000313'::uuid],'주말 런') as room \gset
select public.chat_room_send(:'room','토요일 7시?','00000000-0000-0000-0000-000000000041');
select public.chat_room_send(:'room','토요일 7시?','00000000-0000-0000-0000-000000000041');
select public.chat_room_read(:'room') as data \gset
select pg_temp.check_room(:'data'::jsonb->'room'->>'title'='주말 런' and jsonb_array_length(:'data'::jsonb->'members')=3
  and jsonb_array_length(:'data'::jsonb->'messages')=1,'단톡 생성·재전송 중복 없음');
select pg_temp.check_room((:'data'::jsonb->'messages'->0->>'unread')::int=2,'두 명이 안 읽음');

-- 312가 읽으면 안 읽은 사람이 1명이 되고, 312의 목록·총 개수에 반영됩니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000312',true);
select pg_temp.check_room(public.chat_rooms_unread_total()=1,'312 안 읽은 수');
select pg_temp.check_room((public.my_chat_rooms()->0->>'unread')::int=1 and public.my_chat_rooms()->0->>'title'='주말 런','312 목록');
select public.chat_room_mark_read(:'room',9223372036854775807);
select pg_temp.check_room(public.chat_rooms_unread_total()=0,'읽음 처리');
select pg_temp.check_room((public.chat_room_read(:'room')->'messages'->0->>'unread')::int=1,'한 명만 안 읽음');

-- 실시간 신호는 참여자 주제로만 갑니다.
select set_config('realtime.topic','chat:00000000-0000-0000-0000-000000000312',true);
select pg_temp.check_room((select count(*)>0 from realtime.messages),'참여자 신호');

-- 휴대폰 알림: 아직 안 읽은 313에게만(312는 기기가 있지만 이미 읽음)
reset role;
set local role service_role;
select pg_temp.check_room(jsonb_array_length(public.claim_push_deliveries())=0,'읽은 사람에게는 알리지 않음');
reset role;

-- 참여자가 아닌 사람은 읽기·보내기 금지
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000314',true);
select pg_temp.check_room(pg_temp.fails(format('select public.chat_room_read(%L)',:'room'),'42501'),'비참여자 읽기 거부');
select pg_temp.check_room(pg_temp.fails(format('select public.chat_room_send(%L,''hi'',gen_random_uuid())',:'room'),'42501'),'비참여자 전송 거부');

-- 크루 대화방: 크루원만, 크루마다 하나
select pg_temp.check_room(pg_temp.fails(format('select public.crew_chat_room(%L)',:'crew'),'42501'),'크루원 아니면 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000313',true);
select public.crew_chat_room(:'crew') as crew_room \gset
select pg_temp.check_room(public.crew_chat_room(:'crew')=:'crew_room'::uuid,'크루 대화방 하나');
select public.chat_room_send(:'crew_room','크루 공지','00000000-0000-0000-0000-000000000042');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000311',true);
select pg_temp.check_room((select count(*)=1 from jsonb_array_elements(public.my_chat_rooms()) r
  where r->>'kind'='crew' and r->>'title'='단톡크루' and (r->>'unread')::int=1),'크루 대화방 목록');
select pg_temp.check_room(pg_temp.fails(format('select public.leave_chat_room(%L)',:'crew_room'),'P0001'),'크루 대화방 나가기 거부');

-- 단톡 나가기: 모두 나가면 대화방이 사라집니다.
select public.leave_chat_room(:'room');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000312',true);
select public.leave_chat_room(:'room');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000313',true);
select public.leave_chat_room(:'room');
reset role;
select pg_temp.check_room(not exists(select 1 from runspot_private.chat_rooms where id=:'room'),'모두 나가면 삭제');
set local role anon;
select pg_temp.check_room(pg_temp.fails('select public.my_chat_rooms()','42501'),'익명 거부');
rollback;
