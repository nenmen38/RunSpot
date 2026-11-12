\set ON_ERROR_STOP on
begin;
create function pg_temp.check_chat(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.denied(statement text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when insufficient_privilege then return true; end; $$;

insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000251','chat251@example.com',now()),
 ('00000000-0000-0000-0000-000000000252','chat252@example.com',now()),
 ('00000000-0000-0000-0000-000000000253','chat253@example.com',now());
update public.profiles set nickname='대화검증'||right(id::text,3),visibility='friends'
where id::text like '%00000000025_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000251','00000000-0000-0000-0000-000000000252','00000000-0000-0000-0000-000000000251','accepted');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select pg_temp.check_chat(pg_temp.denied(
  'select public.friend_chat_send(''00000000-0000-0000-0000-000000000253'',''메시지'',''00000000-0000-0000-0000-000000000001'')'),'친구가 아니면 전송 금지');
select public.friend_chat_send('00000000-0000-0000-0000-000000000252','테스트 메시지','00000000-0000-0000-0000-000000000002');
select public.friend_chat_send('00000000-0000-0000-0000-000000000252','테스트 메시지','00000000-0000-0000-0000-000000000002');
select public.group_action(null,'invite_and_start','00000000-0000-0000-0000-000000000252') as group_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000252',true);
select pg_temp.check_chat(public.friend_chat_read('00000000-0000-0000-0000-000000000251')->0->>'body'='테스트 메시지','수신자가 기록 조회');
select pg_temp.check_chat(jsonb_array_length(public.friend_chat_read('00000000-0000-0000-0000-000000000251'))=1,'재시도 중복 저장 금지');
select pg_temp.check_chat(jsonb_array_length(public.friend_chat_read())=1,'대화 목록에 표시');
select public.group_action(:'group_id','accept');
select public.group_action(:'group_id','accept');
reset role;
select pg_temp.check_chat((select state='scheduled' and starts_at between clock_timestamp()+interval '9 seconds' and clock_timestamp()+interval '11 seconds'
  from runspot_private.running_groups where id=:'group_id'),'수락만으로 10초 뒤 출발');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000253',true);
select pg_temp.check_chat(public.friend_chat_read()='[]'::jsonb and pg_temp.denied(
  'select public.friend_chat_read(''00000000-0000-0000-0000-000000000251'')'),'제삼자 조회 금지');
select pg_temp.check_chat(pg_temp.denied('select * from runspot_private.friend_messages'),'직접 테이블 조회 금지');
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values
  ('00000000-0000-0000-0000-000000000252','00000000-0000-0000-0000-000000000251');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select pg_temp.check_chat(public.friend_chat_read()='[]'::jsonb and pg_temp.denied(
  'select public.friend_chat_send(''00000000-0000-0000-0000-000000000252'',''메시지'',''00000000-0000-0000-0000-000000000001'')'),'차단 후 목록 및 전송 차단');
rollback;
