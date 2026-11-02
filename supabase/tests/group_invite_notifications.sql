\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
create function pg_temp.invite(viewer uuid) returns jsonb language sql as $$
  select n from jsonb_array_elements(public.my_notifications()) n where n->>'kind'='group_invite' limit 1;
$$;
grant execute on function pg_temp.invite(uuid) to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000191','ginvite191@example.com',now()),
 ('00000000-0000-0000-0000-000000000192','ginvite192@example.com',now()),
 ('00000000-0000-0000-0000-000000000193','ginvite193@example.com',now());
update public.profiles set nickname='초대검증'||right(id::text,3),visibility='friends' where id::text like '%00000000019_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000192','00000000-0000-0000-0000-000000000191','accepted'),
 ('00000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000193','00000000-0000-0000-0000-000000000191','accepted');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select public.group_action(null,'create') as group_id \gset
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000192');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000192');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000193');
-- 방장 자신은 초대 알림을 받지 않습니다.
select pg_temp.assert_true(public.unread_notification_count()=0,'방장 알림 없음');

-- 초대받은 사람에게 응답할 수 있는 알림이 한 번만 갑니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select pg_temp.assert_true(public.unread_notification_count()=1,'초대 알림 한 번');
select pg_temp.assert_true((select n->>'group_id'=:'group_id' and n->>'nickname'='초대검증191'
  and n->>'invite_status'='invited' and (n->>'can_respond')::boolean and n->'post_id'='null'::jsonb
  from (select pg_temp.invite(null) n) x),'초대 알림 내용');
-- 알림에서 수락하면 기존 그룹 수락과 같이 참여됩니다.
select public.group_action(:'group_id','accept');
select pg_temp.assert_true((select n->>'invite_status'='accepted' and not (n->>'can_respond')::boolean
  from (select pg_temp.invite(null) n) x),'수락 후 응답 버튼 숨김');
select pg_temp.assert_true((public.group_dashboard()->'groups'->0->>'my_status')='accepted','수락 시 그룹 참여');

-- 거절하면 거절 상태가 남습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000193',true);
select public.group_action(:'group_id','reject');
select pg_temp.assert_true((select n->>'invite_status'='declined' and not (n->>'can_respond')::boolean
  from (select pg_temp.invite(null) n) x),'거절 상태 표시');

-- 방장을 차단하면 초대 알림이 보이지 않습니다.
select public.change_my_block('00000000-0000-0000-0000-000000000191',true);
select pg_temp.assert_true(pg_temp.invite(null) is null,'차단한 방장 초대 숨김');

-- 게시판 알림과 함께 쓰여도 목록이 깨지지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select public.create_board_post(gen_random_uuid(),'national','초대 확인 글','내용','tip') as post_id \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select public.set_board_like(:'post_id',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select pg_temp.assert_true(jsonb_array_length(public.my_notifications())=2,'게시판·초대 알림 함께 표시');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.notifications','42501'),'알림 원본 접근 거부');
reset role;
-- 그룹이 지워지면 초대 알림도 함께 지워집니다.
delete from runspot_private.running_groups where id=:'group_id';
select pg_temp.assert_true((select count(*)=0 from runspot_private.notifications where kind='group_invite'),'그룹 삭제 시 알림 정리');
rollback;
