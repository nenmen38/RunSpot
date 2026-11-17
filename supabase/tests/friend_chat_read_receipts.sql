\set ON_ERROR_STOP on
begin;
create function pg_temp.check_read(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000261','read261@example.com',now()),
 ('00000000-0000-0000-0000-000000000262','read262@example.com',now()),
 ('00000000-0000-0000-0000-000000000263','read263@example.com',now());
update public.profiles set nickname='읽음검증'||right(id::text,3),visibility='friends' where id::text like '%00000000026_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000261','00000000-0000-0000-0000-000000000262','00000000-0000-0000-0000-000000000261','accepted');

set local role authenticated;
-- 261이 두 번 보내면 262가 읽기 전까지 '1'(read=false)이고, 262의 목록에는 안 읽은 2개가 보입니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000261',true);
select public.friend_chat_send('00000000-0000-0000-0000-000000000262','안녕','00000000-0000-0000-0000-000000000011');
select public.friend_chat_send('00000000-0000-0000-0000-000000000262','뛰러 갈래?','00000000-0000-0000-0000-000000000012');
select pg_temp.check_read((select bool_and(not (m->>'read')::boolean)
  from jsonb_array_elements(public.friend_chat_read('00000000-0000-0000-0000-000000000262')) m),'보낸 직후 안 읽음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000262',true);
select pg_temp.check_read((public.friend_chat_read()->0->>'unread')::int=2,'안 읽은 메시지 수');
select (public.friend_chat_read('00000000-0000-0000-0000-000000000261')->1->>'id')::bigint as first_id \gset
select (public.friend_chat_read('00000000-0000-0000-0000-000000000261')->0->>'id')::bigint as last_id \gset
-- 받은 메시지는 내 화면에서 항상 읽음입니다.
select pg_temp.check_read((select bool_and((m->>'read')::boolean)
  from jsonb_array_elements(public.friend_chat_read('00000000-0000-0000-0000-000000000261')) m),'받은 메시지는 1 없음');

-- 첫 메시지까지만 읽으면 두 번째만 '1'이 남습니다.
select public.friend_chat_mark_read('00000000-0000-0000-0000-000000000261',:first_id);
select pg_temp.check_read((public.friend_chat_read()->0->>'unread')::int=1,'하나 읽음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000261',true);
select pg_temp.check_read((select array_agg((m->>'read')::boolean order by (m->>'id')::bigint)=array[true,false]
  from jsonb_array_elements(public.friend_chat_read('00000000-0000-0000-0000-000000000262')) m),'첫 메시지만 읽음');

-- 끝까지 읽으면 '1'이 모두 사라지고, 예전 위치로 되돌리거나 남의 메시지 범위를 넘길 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000262',true);
select pg_temp.check_read(public.friend_chat_mark_read('00000000-0000-0000-0000-000000000261',:last_id+1000)=:last_id,'받은 범위까지만');
select pg_temp.check_read(public.friend_chat_mark_read('00000000-0000-0000-0000-000000000261',:first_id)=:last_id,'되돌리기 금지');
select pg_temp.check_read((public.friend_chat_read()->0->>'unread')::int=0,'모두 읽음');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000261',true);
select pg_temp.check_read((select bool_and((m->>'read')::boolean)
  from jsonb_array_elements(public.friend_chat_read('00000000-0000-0000-0000-000000000262')) m),'1 모두 사라짐');
-- 내가 보낸 메시지는 내 안 읽음 수에 들어가지 않습니다.
select pg_temp.check_read((public.friend_chat_read()->0->>'unread')::int=0,'보낸 메시지는 안 읽음 아님');

-- 친구가 아니면 읽음 처리할 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000263',true);
select pg_temp.check_read(pg_temp.fails(
  'select public.friend_chat_mark_read(''00000000-0000-0000-0000-000000000261'',1)','42501'),'제삼자 읽음 금지');
reset role;
set local role anon;
select pg_temp.check_read(pg_temp.fails(
  'select public.friend_chat_mark_read(''00000000-0000-0000-0000-000000000261'',1)','42501'),'익명 금지');
rollback;
