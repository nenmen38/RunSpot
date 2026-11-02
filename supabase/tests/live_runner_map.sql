\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end;
$$;
create function pg_temp.fails(statement text,expected_code text)
returns boolean language plpgsql security invoker as $$
begin execute statement; return false;
exception when others then return sqlstate=expected_code; end;
$$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000012'),
 ('00000000-0000-0000-0000-000000000013');
update auth.users set email=id::text || '@example.com',email_confirmed_at=now();
update public.profiles set nickname='러너' || right(id::text,2);
update public.profiles set visibility='public';
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(37,127,10)','42501'),'비로그인 위치 업로드 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select public.update_my_live_location(37,127,10);
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.live_locations','42501'),'위치 원본 직접 접근 차단');
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(100,127,10)','22023'),'잘못된 위도 차단');
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(37,127,500)','22023'),'부정확한 위치 차단');
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(''NaN''::float8,127,10)','22023'),'비정상 좌표 차단');
select public.update_my_live_location(38,128,10);
reset role;
select pg_temp.assert_true((select latitude=37 from runspot_private.live_locations where user_id='00000000-0000-0000-0000-000000000011'),'연속 업로드 빈도 제한');
select pg_temp.assert_true((select count(*)=1 from runspot_private.live_locations),'본인 위치만 생성');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
select public.update_my_live_location(37.001,127,10);
select pg_temp.assert_true((select count(*)=1 from public.map_nearby_runners()),'주변 공개 러너 조회');
select pg_temp.assert_true((select nickname='러너11' and distance_m between 100 and 120 from public.map_nearby_runners()),'닉네임 및 실제 거리 반환');
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners(10)),'거리 밖 러너 차단');
select pg_temp.assert_true(pg_temp.fails('select public.map_nearby_runners(6000)','22023'),'과도한 조회 반경 차단');
reset role;
insert into runspot_private.blocks values('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012');
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners()),'차단한 러너 위치 제외');
reset role;
delete from runspot_private.blocks;
update public.profiles set visibility='friends' where id='00000000-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners()),'친구 아닌 사용자 위치 보호');
reset role;
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000011','accepted');
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.map_nearby_runners()),'수락한 친구 위치 조회');
select set_config('realtime.topic','runner-map',true);
select pg_temp.assert_true((select count(*)>0 from realtime.messages),'인증된 사용자 변경 신호 수신');
select pg_temp.assert_true((select bool_and(payload='{}'::jsonb) from realtime.messages),'방송에 좌표나 사용자 식별자 없음');
select pg_temp.assert_true(pg_temp.fails('insert into realtime.messages(extension,payload) values(''broadcast'',''{}'')','42501'),'클라이언트 방송 쓰기 차단');
select set_config('realtime.topic','other-channel',true);
select pg_temp.assert_true((select count(*)=0 from realtime.messages),'다른 채널 접근 차단');
reset role;
update runspot_private.live_locations set updated_at=now()-interval '3 minutes'
  where user_id='00000000-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners()),'갱신이 멈춘 러너 위치 제외');
reset role;
update runspot_private.live_locations set updated_at=now();
update runspot_private.account_controls set status='suspended'
  where user_id='00000000-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners()),'정지된 러너 위치 제외');
reset role;
update runspot_private.account_controls set status='active';
set local role authenticated;
select public.stop_live_location();
reset role;
select pg_temp.assert_true((select count(*)=1 from runspot_private.live_locations),'공유 종료는 본인 위치만 삭제');
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000011';
select pg_temp.assert_true((select count(*)=0 from runspot_private.live_locations),'비공개 전환 시 원본 삭제');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(37,127,10)','42501'),'비공개 사용자 업로드 차단');
reset role;
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000013';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(37,127,10)','42501'),'이메일 미인증 업로드 차단');
select set_config('realtime.topic','runner-map',true);
select pg_temp.assert_true((select count(*)=0 from realtime.messages),'미인증 사용자 방송 수신 차단');
reset role;
rollback;
\echo '실시간 러너 지도 권한 테스트 통과'

begin;
create function pg_temp.browse_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.browse_fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'browse'||n||'@example.com',now() from generate_series(901,905) n;
update public.profiles set nickname='조회'||right(id::text,3),visibility='public' where id::text like '%00000000090_';
update public.profiles set visibility='friends' where id in ('00000000-0000-0000-0000-000000000903','00000000-0000-0000-0000-000000000904');
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','00000000-0000-0000-0000-000000000901','accepted');
insert into runspot_private.blocks(blocker_id,blocked_id) values
 ('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000905');
insert into runspot_private.live_locations(user_id,latitude,longitude)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,37.001,127 from generate_series(902,905) n;
set local role anon;
select pg_temp.browse_assert(pg_temp.browse_fails('select * from public.map_nearby_runners_at(37,127)','42501'),'비로그인 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000901',true);
select pg_temp.browse_assert((select count(*)=2 from public.map_nearby_runners_at(37,127)),'공유·러닝 기록 없이 공개 러너와 수락한 친구만 조회');
select pg_temp.browse_assert((select count(*)=0 from public.map_nearby_runners_at(37,127,10)),'조회 반경 적용');
select pg_temp.browse_assert(pg_temp.browse_fails('select * from public.map_nearby_runners_at(''NaN''::float8,127)','22023'),'비정상 좌표 차단');
select pg_temp.browse_assert(pg_temp.browse_fails('select * from public.map_nearby_runners_at(37,127,6000)','22023'),'과도한 반경 차단');
reset role;
select pg_temp.browse_assert(not exists(select 1 from runspot_private.live_locations where user_id='00000000-0000-0000-0000-000000000901'),'조회자 위치를 저장·공개하지 않음');
update runspot_private.live_locations set updated_at=now()-interval '3 minutes';
set local role authenticated;
select pg_temp.browse_assert((select count(*)=0 from public.map_nearby_runners_at(37,127)),'갱신이 멈춘 러너 제외');
reset role;
update runspot_private.live_locations set updated_at=now();
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000902';
set local role authenticated;
select pg_temp.browse_assert((select count(*)=1 from public.map_nearby_runners_at(37,127)),'비공개 전환 즉시 반영');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000901';
set local role authenticated;
select pg_temp.browse_assert(pg_temp.browse_fails('select * from public.map_nearby_runners_at(37,127)','42501'),'정지 조회자 차단');
reset role;
rollback;
\echo '공유하지 않는 홈 주변 러너 조회·공개 범위·차단 테스트 통과'
