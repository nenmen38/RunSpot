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
create function pg_temp.connection_id(target uuid)
returns uuid language sql security invoker as $$
  select (e->>'relationship_id')::uuid from jsonb_array_elements(public.friend_dashboard()->'entries') e
    where e->>'user_id'=target::text;
$$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000041'),
 ('00000000-0000-0000-0000-000000000042'),
 ('00000000-0000-0000-0000-000000000043'),
 ('00000000-0000-0000-0000-000000000044'),
 ('00000000-0000-0000-0000-000000000045');
update auth.users set email=id::text || '@example.com',email_confirmed_at=now()
  where id::text like '%00000000004_';
update public.profiles set nickname='Friend'||right(id::text,2),visibility='friends'
  where id::text like '%00000000004_';
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000043';

set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.friend_dashboard()','42501'),'비로그인 목록 차단');
select pg_temp.assert_true(pg_temp.fails('select public.search_friend(''Friend42'')','42501'),'비로그인 검색 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000042'',''request'')','42501'),'비로그인 요청 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000041',true);
select pg_temp.assert_true((public.friend_dashboard()->>'can_interact')::boolean,'인증된 활성 계정');
select pg_temp.assert_true((select count(*)=1 from public.search_friend('friend42')),'대소문자 무관 정확한 닉네임 검색');
select pg_temp.assert_true((select count(*)=0 from public.search_friend('Friend')),'부분 닉네임 검색 제외');
select pg_temp.assert_true((select count(*)=0 from public.search_friend('Friend41')),'본인 검색 제외');
select pg_temp.assert_true((select count(*)=0 from public.search_friend('Friend43')),'비공개 신규 사용자 검색 제외');
select pg_temp.assert_true(pg_temp.fails('select public.search_friend(''%'')','22023'),'와일드카드 검색 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000041'',''request'')','22023'),'자기 자신에게 요청 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000043'',''request'')','42501'),'비공개 대상 직접 요청 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000099'',''request'')','42501'),'없는 사용자 직접 요청 차단');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.friend_request_limits','42501'),'발송 제한 원본 조회 차단');
select pg_temp.assert_true(pg_temp.fails('insert into public.friendships(user_low,user_high,requested_by,status) values(''00000000-0000-0000-0000-000000000041'',''00000000-0000-0000-0000-000000000042'',''00000000-0000-0000-0000-000000000041'',''accepted'')','42501'),'친구 직접 생성 차단');
select public.change_friend('00000000-0000-0000-0000-000000000042','request');
select public.change_friend('00000000-0000-0000-0000-000000000042','request');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=1,'중복 요청은 한 관계만 생성');
select pg_temp.assert_true(public.friend_dashboard()->'entries'->0->>'relation'='sent','요청자에게 보낸 요청 표시');
select pg_temp.connection_id('00000000-0000-0000-0000-000000000042') as original_id \gset
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''accept'',%L)','00000000-0000-0000-0000-000000000042',:'original_id'),'42501'),'요청자의 자기 수락 차단');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''reject'',%L)','00000000-0000-0000-0000-000000000042',:'original_id'),'42501'),'요청자의 받은 요청 거절 차단');
select pg_temp.assert_true(pg_temp.fails('update public.friendships set status=''accepted''','42501'),'친구 직접 수정 차단');
select pg_temp.assert_true(pg_temp.fails('delete from public.friendships','42501'),'친구 직접 삭제 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000044'',''request'')','P0001'),'빠른 반복 전송 차단');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000044',true);
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'타인 관계 목록 제외');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''accept'',%L)','00000000-0000-0000-0000-000000000042',:'original_id'),'P0001'),'제삼자의 관계 변경 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000042',true);
select pg_temp.assert_true(public.friend_dashboard()->'entries'->0->>'relation'='received','수신자에게 받은 요청 표시');
select public.change_friend('00000000-0000-0000-0000-000000000041','request');
select pg_temp.assert_true(public.friend_dashboard()->'entries'->0->>'relation'='received','상호 요청을 자동 수락하지 않음');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''cancel'',%L)','00000000-0000-0000-0000-000000000041',:'original_id'),'42501'),'수신자의 보낸 요청 취소 차단');
select public.change_friend('00000000-0000-0000-0000-000000000041','accept',:'original_id');
select public.change_friend('00000000-0000-0000-0000-000000000041','accept',:'original_id');
select pg_temp.assert_true(public.friend_dashboard()->'entries'->0->>'relation'='friend','수락 및 재시도의 멱등성');
select pg_temp.assert_true((select visibility='friends' from public.profiles where id=auth.uid()),'수락이 공개 설정을 변경하지 않음');

-- 기존 지도 권한은 친구 수락으로 허용되고 삭제로 즉시 회수됩니다.
select public.update_my_live_location(37.001,127,10);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000041',true);
select public.update_my_live_location(37,127,10);
select pg_temp.assert_true((select count(*)=1 from public.map_nearby_runners()),'수락한 친구의 위치만 조회');
select public.change_friend('00000000-0000-0000-0000-000000000042','remove',:'original_id');
select pg_temp.assert_true((select count(*)=0 from public.map_nearby_runners()),'친구 삭제 시 위치 접근 회수');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'친구 삭제 후 목록 정리');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''remove'',%L)','00000000-0000-0000-0000-000000000042',:'original_id'),'P0001'),'삭제된 관계 재요청은 오래된 상태로 처리');
reset role;
update runspot_private.friend_request_limits set last_sent_at=now()-interval '10 seconds';
set local role authenticated;
select public.change_friend('00000000-0000-0000-0000-000000000042','request');
select pg_temp.connection_id('00000000-0000-0000-0000-000000000042') as new_id \gset
select pg_temp.assert_true(:'original_id'<>:'new_id','재요청은 새 관계 식별자 사용');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''cancel'',%L)','00000000-0000-0000-0000-000000000042',:'original_id'),'P0001'),'오래된 화면은 새 요청을 취소하지 못함');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000042',true);
select public.change_friend('00000000-0000-0000-0000-000000000041','reject',:'new_id');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'거절 후 양쪽 목록 정리');
reset role;
update runspot_private.friend_request_limits set last_sent_at=now()-interval '10 seconds',sent_count=30;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000041',true);
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000042'',''request'')','P0001'),'취소와 재요청도 시간당 제한 적용');
reset role;
update runspot_private.friend_request_limits set window_started_at=now()-interval '2 hours',last_sent_at=now()-interval '10 seconds';
set local role authenticated;
select public.change_friend('00000000-0000-0000-0000-000000000042','request');
select pg_temp.connection_id('00000000-0000-0000-0000-000000000042') as cancel_id \gset
select public.change_friend('00000000-0000-0000-0000-000000000042','cancel',:'cancel_id');
reset role;
select pg_temp.assert_true((select sent_count=1 from runspot_private.friend_request_limits where user_id='00000000-0000-0000-0000-000000000041'),'시간 경과 후 발송 예산 초기화');

-- 비공개 발신자가 공개된 상대에게 보내는 요청은 닉네임만 의도적으로 공개합니다.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000043',true);
select public.change_friend('00000000-0000-0000-0000-000000000042','request');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000042',true);
select pg_temp.assert_true(public.friend_dashboard()->'entries'->0->>'nickname'='Friend43','받은 요청의 비공개 발신자 닉네임 표시');
select pg_temp.connection_id('00000000-0000-0000-0000-000000000043') as private_id \gset
reset role;
insert into runspot_private.blocks values('00000000-0000-0000-0000-000000000043','00000000-0000-0000-0000-000000000042');
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.search_friend('Friend43')),'차단 상대 검색 제외');
select pg_temp.assert_true(jsonb_array_length(public.friend_dashboard()->'entries')=0,'차단 상대 요청 제외');
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''accept'',%L)','00000000-0000-0000-0000-000000000043',:'private_id'),'42501'),'차단 상대 수락 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000043',true);
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000042'',''request'')','42501'),'반대 방향 차단 요청 차단');
reset role;
delete from runspot_private.blocks where blocker_id='00000000-0000-0000-0000-000000000043';
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000043';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000042',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.change_friend(%L,''accept'',%L)','00000000-0000-0000-0000-000000000043',:'private_id'),'42501'),'인증 취소된 상대 수락 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000043',true);
select pg_temp.assert_true(not (public.friend_dashboard()->>'can_interact')::boolean,'미인증 계정 개인 목록 조회 허용');
select pg_temp.assert_true(pg_temp.fails('select public.search_friend(''Friend42'')','42501'),'미인증 검색 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000042'',''request'')','42501'),'미인증 요청 차단');
select public.change_friend('00000000-0000-0000-0000-000000000042','cancel',:'private_id');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000044';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000041',true);
select pg_temp.assert_true((select count(*)=0 from public.search_friend('Friend44')),'정지 대상 검색 차단');
select pg_temp.assert_true(pg_temp.fails('select public.change_friend(''00000000-0000-0000-0000-000000000044'',''request'')','42501'),'정지 대상 요청 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000044',true);
select pg_temp.assert_true(pg_temp.fails('select public.friend_dashboard()','42501'),'정지 계정 목록 차단');
reset role;
rollback;
\echo '친구 검색 및 상태 전이 권한 테스트 통과'
