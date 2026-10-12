\set ON_ERROR_STOP on
begin;
-- 실패하면 즉시 예외를 발생시키고 전체 테스트 데이터를 되돌립니다.
create function pg_temp.assert_true(ok boolean, message text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.denied(statement text)
returns boolean language plpgsql security invoker as $$
begin
  execute statement;
  return false;
exception when insufficient_privilege then return true;
end;
$$;

insert into auth.users(id) values
('00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000003');
select runspot_private.finish_registration(id) from auth.users;
update auth.users set email=id::text || '@example.com', email_confirmed_at=now()
where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
update public.profiles set nickname=case when right(id::text,1)='1' then '테스트러너' else 'runner_' || right(id::text,1) end;
update public.profiles set visibility='public';
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',
'20000000-0000-0000-0000-000000000001','2026-09-20 00:00:00Z','2026-09-20 00:30:00Z',5000,1800,'verified');
insert into public.posts(id,run_id,user_id,visibility,distance_m,duration_sec)
values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
'00000000-0000-0000-0000-000000000001','friends',5000,1800);
insert into public.run_share_paths(post_id,encoded_polyline,sanitizer_version)
values ('30000000-0000-0000-0000-000000000001','test','test');
insert into runspot_private.user_roles(user_id,role)
values ('00000000-0000-0000-0000-000000000003','admin');
select pg_temp.assert_true((select count(*)=5 from public.route_presets),'프리셋 초기 데이터');
select pg_temp.assert_true((select count(*)=3 from public.achievement_definitions),'업적 초기 데이터');

set local role anon;
select pg_temp.assert_true(pg_temp.denied('select * from public.profiles'),'비로그인 조회 차단');
select pg_temp.assert_true(pg_temp.denied('select public.my_staff_role()'),'비로그인 역할 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.runs),'본인 러닝 조회');
select pg_temp.assert_true((select count(*)=1 from public.posts),'본인 게시물 조회');
select pg_temp.assert_true(pg_temp.denied('update public.profiles set nickname=''다른이름'' where id=auth.uid()'),'닉네임 직접 수정 차단');
select pg_temp.assert_true((select nickname='테스트러너' from public.profiles where id=auth.uid()),'본인 닉네임 조회');
select pg_temp.assert_true(pg_temp.denied('update public.profiles set id=gen_random_uuid()'),'소유자 변경 차단');
select pg_temp.assert_true(pg_temp.denied('update public.runs set distance_m=100000'),'기록 변조 차단');
select pg_temp.assert_true(pg_temp.denied('insert into public.runs default values'),'기록 직접 생성 차단');
select pg_temp.assert_true(pg_temp.denied('select * from runspot_private.run_tracks'),'GPS 직접 조회 차단');
select pg_temp.assert_true(pg_temp.denied('insert into runspot_private.user_roles(user_id,role) values(auth.uid(),''admin'')'),'권한 상승 차단');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.runs),'타인 러닝 원본 차단');
select pg_temp.assert_true((select count(*)=0 from public.posts),'친구 아닌 사용자 차단');
select pg_temp.assert_true((select count(*)=0 from public.run_share_paths),'경로 우회 조회 차단');
select pg_temp.assert_true(pg_temp.denied('update public.profiles set nickname=''침입'' where id=''00000000-0000-0000-0000-000000000001'''),'타인 닉네임 직접 수정 차단');
select pg_temp.assert_true((select nickname='테스트러너' from public.profiles where id='00000000-0000-0000-0000-000000000001'),'타인 프로필 수정 차단');
reset role;
insert into public.friendships(user_low,user_high,requested_by,status) values
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','accepted');
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.posts),'친구 게시물 조회');
select pg_temp.assert_true((select count(*)=1 from public.run_share_paths),'친구 가공 경로 조회');
reset role;
insert into runspot_private.blocks values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.posts),'차단 시 친구 공개 철회');
reset role;
delete from runspot_private.blocks;
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.posts),'위치 비공개와 게시물 공개 범위는 독립');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"aal":"aal1","user_role":"admin"}',true);
select pg_temp.assert_true(public.my_staff_role() is null,'관리자 다중 인증 필수');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true(public.my_staff_role()='admin','다중 인증 관리자 허용');
reset role;
delete from runspot_private.user_roles where user_id='00000000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.assert_true(public.my_staff_role() is null,'역할 회수 즉시 적용');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from public.runs),'정지 계정 조회 차단');
reset role;
set local role service_role;
select pg_temp.assert_true(pg_temp.denied('delete from runspot_private.audit_logs'),'서비스 역할 감사 로그 삭제 차단');
reset role;
update runspot_private.account_controls set status='active';
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not public.my_email_verified(),'이메일만 입력한 계정은 미인증');
select pg_temp.assert_true((select count(*)=1 from public.runs),'미인증 계정 개인 기록 허용');
select pg_temp.assert_true((select count(*)=5 from public.route_presets),'미인증 계정 코스 허용');
select pg_temp.assert_true(pg_temp.denied('update public.profiles set visibility=''public'' where id=auth.uid()'),'미인증 공개 범위 변경 차단');
select pg_temp.assert_true(pg_temp.denied('insert into public.comments(post_id,body) values(''30000000-0000-0000-0000-000000000001'',''댓글'')'),'미인증 댓글 차단');
select pg_temp.assert_true(pg_temp.denied('select public.publish_run(''10000000-0000-0000-0000-000000000001'',''글'',''public'')'),'미인증 게시물 차단');
select pg_temp.assert_true(pg_temp.denied('select runspot_private.email_verified(''00000000-0000-0000-0000-000000000002'')'),'타인 인증 상태 조회 차단');
reset role;
update auth.users set email_confirmed_at=now(),email_change='next@example.com' where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true(not public.my_email_verified(),'이메일 변경 중에는 재인증 필요');
select pg_temp.assert_true((select count(*)=1 from public.runs),'이메일 변경 중 개인 기록 접근 허용');
reset role;
update auth.users set email_change='' where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true(public.my_email_verified(),'인증 완료 계정 확인');
select pg_temp.assert_true((select count(*)=1 from public.runs),'인증 완료 후 접근 복원');
reset role;
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
values ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',
'20000000-0000-0000-0000-000000000002','2026-09-21 00:00:00Z','2026-09-21 00:30:00Z',5000,1800,'verified');
set local role authenticated;
select pg_temp.assert_true((select visibility='private' from public.profiles where id=auth.uid()),'이메일 변경 시 비공개 초기화');
select pg_temp.assert_true(public.publish_run('10000000-0000-0000-0000-000000000002','비공개 사용자 글','public') is not null,'인증된 비공개 사용자 게시물 작성');
insert into public.comments(post_id,body) values ('30000000-0000-0000-0000-000000000001','비공개 사용자 댓글');
select pg_temp.assert_true((select count(*)=1 from public.comments),'인증된 비공개 사용자 댓글 작성');
reset role;
insert into runspot_private.live_locations(user_id,latitude,longitude) values
('00000000-0000-0000-0000-000000000001',37,127),
('00000000-0000-0000-0000-000000000002',37.001,127),
('00000000-0000-0000-0000-000000000003',37.002,127);
update public.profiles set visibility='friends' where id='00000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations()),'비공개 사용자는 다른 위치 조회 불가');
update public.profiles set visibility='friends' where id=auth.uid();
select pg_temp.assert_true((select count(*)=1 from public.nearby_locations()),'친구 공개는 친구 위치만');
update public.profiles set visibility='public' where id=auth.uid();
select pg_temp.assert_true((select count(*)=2 from public.nearby_locations()),'전체 공개는 친구 공개 친구와 공개 사용자 조회');
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations(10)),'거리 범위 밖 위치 제외');
select pg_temp.assert_true(pg_temp.denied('select * from runspot_private.live_locations'),'위치 원본 직접 조회 차단');
reset role;
update public.profiles set visibility='friends' where id='00000000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.nearby_locations()),'친구 아닌 친구 공개 사용자 제외');
reset role;
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations()),'상대방 비공개 보호');
reset role;
update public.profiles set visibility='public' where id='00000000-0000-0000-0000-000000000002';
insert into runspot_private.blocks values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations()),'차단된 위치 제외');
reset role;
delete from runspot_private.blocks;
update runspot_private.live_locations set updated_at=now()-interval '3 minutes' where user_id='00000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations()),'오래된 위치 제외');
reset role;
update runspot_private.live_locations set updated_at=now();
update auth.users set email_confirmed_at=null where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.nearby_locations()),'미인증 위치 조회 불가');
reset role;
rollback;
\echo '권한 테스트 통과'
