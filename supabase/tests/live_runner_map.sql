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
update auth.users set phone='8210' || right(replace(id::text,'-',''),8),phone_confirmed_at=now();
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
update auth.users set phone_confirmed_at=null where id='00000000-0000-0000-0000-000000000013';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
select pg_temp.assert_true(pg_temp.fails('select public.update_my_live_location(37,127,10)','42501'),'전화번호 미인증 업로드 차단');
select set_config('realtime.topic','runner-map',true);
select pg_temp.assert_true((select count(*)=0 from realtime.messages),'미인증 사용자 방송 수신 차단');
reset role;
rollback;
\echo '실시간 러너 지도 권한 테스트 통과'
