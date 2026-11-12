\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.runner(target uuid) returns jsonb language sql as $$
  select to_jsonb(r) from public.map_nearby_runners_at(37,127,1000) r where r.user_id=target;
$$;
grant execute on function pg_temp.runner(uuid) to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000211','aura211@example.com',now()),
 ('00000000-0000-0000-0000-000000000212','aura212@example.com',now()),
 ('00000000-0000-0000-0000-000000000213','aura213@example.com',now());
update public.profiles set nickname='오라검증'||right(id::text,3),visibility='public' where id::text like '%00000000021_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000212','00000000-0000-0000-0000-000000000211','accepted');
-- 212는 오라 테두리를 착용했고, 213은 기본 테두리를 샀지만 착용하지 않았습니다.
insert into runspot_private.owned_frames(user_id,frame,coins) values
 ('00000000-0000-0000-0000-000000000212','aura',0),('00000000-0000-0000-0000-000000000213','basic',0);
insert into runspot_private.frame_settings(user_id,frame,color) values
 ('00000000-0000-0000-0000-000000000212','aura','#EF4444'),('00000000-0000-0000-0000-000000000213',null,'#22C55E');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000212',true);
select public.update_my_live_location(37.0001,127,10,330);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000213',true);
-- 페이스를 보내지 않는 이전 앱과 범위를 벗어난 값도 위치는 그대로 저장합니다.
select public.update_my_live_location(37.0002,127,10);
reset role;
select pg_temp.assert_true((select pace_sec=330 from runspot_private.live_locations
  where user_id='00000000-0000-0000-0000-000000000212'),'페이스 저장');
update runspot_private.live_locations set updated_at=updated_at-interval '10 seconds';
set local role authenticated;
select public.update_my_live_location(37.0002,127,10,5);
reset role;
select pg_temp.assert_true((select pace_sec is null and latitude=37.0002 from runspot_private.live_locations
  where user_id='00000000-0000-0000-0000-000000000213'),'범위 밖 페이스는 비움');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000211',true);
-- 친구는 테두리·색·페이스와 친구 표시를 함께 받습니다.
select pg_temp.assert_true((select (r->>'is_friend')::boolean and r->>'frame'='aura'
  and r->>'frame_color'='#EF4444' and (r->>'pace_sec')::int=330 and r->>'nickname'='오라검증212'
  from (select pg_temp.runner('00000000-0000-0000-0000-000000000212') r) x),'친구의 오라와 페이스');
-- 친구가 아니면 페이스는 주지 않고, 착용하지 않은 테두리의 색도 주지 않습니다.
select pg_temp.assert_true((select not (r->>'is_friend')::boolean and r->'frame'='null'::jsonb
  and r->'frame_color'='null'::jsonb and r->'pace_sec'='null'::jsonb
  from (select pg_temp.runner('00000000-0000-0000-0000-000000000213') r) x),'친구가 아닌 러너');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000213',true);
select public.set_frame('basic','#22C55E');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000211',true);
select pg_temp.assert_true((select r->>'frame'='basic' and r->>'frame_color'='#22C55E' and r->'pace_sec'='null'::jsonb
  from (select pg_temp.runner('00000000-0000-0000-0000-000000000213') r) x),'친구가 아닌 러너의 테두리 표시');
-- 차단하면 위치와 함께 테두리 정보도 보이지 않습니다.
select public.change_my_block('00000000-0000-0000-0000-000000000212',true);
select pg_temp.assert_true(pg_temp.runner('00000000-0000-0000-0000-000000000212') is null,'차단 상대 숨김');
rollback;
