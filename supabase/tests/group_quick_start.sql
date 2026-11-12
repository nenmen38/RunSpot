\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000231','quick231@example.com',now()),
 ('00000000-0000-0000-0000-000000000232','quick232@example.com',now()),
 ('00000000-0000-0000-0000-000000000233','quick233@example.com',now());
update public.profiles set nickname='출발검증'||right(id::text,3),visibility='friends' where id::text like '%00000000023_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','00000000-0000-0000-0000-000000000231','accepted'),
 ('00000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000233','00000000-0000-0000-0000-000000000231','accepted');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000231',true);
select public.group_action(null,'create') as group_id \gset
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000232');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000233');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''start'')',:'group_id'),'P0001'),'수락한 친구 없이 출발 금지');

-- 친구 한 명이 수락하면 GPS 준비 없이 바로 출발합니다. 아직 응답하지 않은 초대는 정리됩니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000232',true);
select public.group_action(:'group_id','accept');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000231',true);
select public.group_action(:'group_id','start');
reset role;
select pg_temp.assert_true((select state='scheduled' and starts_at between now()+interval '9 seconds' and now()+interval '11 seconds'
  from runspot_private.running_groups where id=:'group_id'),'준비 없이 10초 뒤 출발');
select pg_temp.assert_true((select status='cancelled' from runspot_private.running_group_members
  where group_id=:'group_id' and user_id='00000000-0000-0000-0000-000000000233'),'응답 없는 초대 정리');

-- 방장이 그룹을 취소하면 그룹·참여자·초대 알림이 모두 지워집니다.
-- 231은 이미 출발한 그룹에 있으므로 233이 새 그룹을 만들어 231을 초대합니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000233',true);
select public.group_action(null,'create') as cancel_group \gset
select public.group_action(:'cancel_group','invite','00000000-0000-0000-0000-000000000231');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000231',true);
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.my_notifications()) n
  where n->>'group_id'=:'cancel_group'),'취소 전 초대 알림');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000233',true);
select public.group_action(:'cancel_group','cancel');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.group_dashboard()->'groups') e
  where e->>'id'=:'cancel_group'),'취소한 그룹은 목록에서 사라짐');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000231',true);
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.group_dashboard()->'groups') e
  where e->>'id'=:'cancel_group'),'초대받은 사람 목록에서도 사라짐');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.my_notifications()) n
  where n->>'group_id'=:'cancel_group'),'취소한 그룹의 초대 알림 정리');
reset role;
select pg_temp.assert_true(not exists(select 1 from runspot_private.running_groups where id=:'cancel_group'),'취소한 그룹 기록 삭제');

-- 알림창 모두 지우기는 내 알림만 지웁니다.
insert into runspot_private.notifications(recipient_id,actor_id,kind,group_id)
select '00000000-0000-0000-0000-000000000232','00000000-0000-0000-0000-000000000231','group_invite',:'group_id'
where not exists(select 1 from runspot_private.notifications where recipient_id='00000000-0000-0000-0000-000000000232');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000232',true);
select pg_temp.assert_true(jsonb_array_length(public.my_notifications())>=1,'지우기 전 알림');
select pg_temp.assert_true(public.clear_my_notifications()>=1,'모두 지우기');
select pg_temp.assert_true(jsonb_array_length(public.my_notifications())=0
  and public.unread_notification_count()=0,'지운 뒤 알림 없음');
select pg_temp.assert_true(public.clear_my_notifications()=0,'지울 알림 없음');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.notifications
  where recipient_id='00000000-0000-0000-0000-000000000232'),'내 알림 삭제');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.clear_my_notifications()','42501'),'비로그인 지우기 거부');
rollback;
