\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000111','group111@example.com',now()),
 ('00000000-0000-0000-0000-000000000112','group112@example.com',now()),
 ('00000000-0000-0000-0000-000000000113','group113@example.com',now()),
 ('00000000-0000-0000-0000-000000000114','group114@example.com',now());
update public.profiles set nickname='그룹'||right(id::text,3),visibility='friends' where id::text like '%00000000011_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','00000000-0000-0000-0000-000000000111','accepted'),
 ('00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000113','00000000-0000-0000-0000-000000000111','accepted');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.group_dashboard()','42501'),'비로그인 그룹 접근 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
select public.group_action(null,'create') as group_id \gset
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.running_groups','42501'),'그룹 원본 접근 금지');
select pg_temp.assert_true(pg_temp.fails('select public.group_action(null,''create'')','P0001'),'중복 활성 그룹 생성 금지');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''invite'',''00000000-0000-0000-0000-000000000114'')',:'group_id'),'42501'),'친구 아닌 사용자 초대 금지');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000112');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000112');
select public.group_action(:'group_id','invite','00000000-0000-0000-0000-000000000113');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''start'')',:'group_id'),'P0001'),'두 명 이상 준비 필요');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000114',true);
select pg_temp.assert_true(jsonb_array_length(public.group_dashboard()->'groups')=0,'제삼자 그룹 비공개');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''accept'')',:'group_id'),'42501'),'초대 없는 참여 금지');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',true);
select pg_temp.assert_true(jsonb_array_length(public.group_dashboard()->'groups'->0->'members')=2,'초대 수락 전 타 참여자 비공개');
select public.group_action(:'group_id','accept');
select public.group_action(:'group_id','accept');
select pg_temp.assert_true(jsonb_array_length(public.group_dashboard()->'groups'->0->'members')=2,'동의하지 않은 다른 초대자의 닉네임 비공개');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''start'')',:'group_id'),'42501'),'방장 아닌 사용자 출발 예약 금지');
select public.group_action(:'group_id','ready');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000113',true);
select public.group_action(:'group_id','reject');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
select public.group_action(:'group_id','ready');
select public.group_action(:'group_id','start');
select public.group_action(:'group_id','start');
select pg_temp.assert_true(public.group_dashboard()->'groups'->0->>'state'='scheduled','공동 출발 예약');
reset role;
select pg_temp.assert_true((select starts_at between now()+interval '9 seconds' and now()+interval '11 seconds' from runspot_private.running_groups where id=:'group_id'),'서버 기준 10초 뒤 출발');
update runspot_private.running_groups set starts_at=now()-interval '1 minute' where id=:'group_id';
set local role authenticated;
select public.group_action(:'group_id','join_run',null,'10000000-0000-0000-0000-000000000111');
select public.group_action(:'group_id','join_run',null,'10000000-0000-0000-0000-000000000111');
select public.save_my_run('10000000-0000-0000-0000-000000000111',now()-interval '1 minute',now(),150,60);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',true);
select public.save_my_run('10000000-0000-0000-0000-000000000112',now()-interval '1 minute',now(),160,60);
select public.group_action(:'group_id','join_run',null,'10000000-0000-0000-0000-000000000112');
select public.group_action(:'group_id','join_run',null,'10000000-0000-0000-0000-000000000112');
select pg_temp.assert_true(public.group_dashboard()->'groups'->0->>'state'='finished','모든 참여자 완료 시 그룹 종료');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.group_dashboard()->'groups'->0->'members')e where e->>'distance_m' is not null),'개인 기록 저장 후 그룹 결과 반영');
select pg_temp.assert_true(not (public.group_dashboard()::text like '%latitude%'),'그룹에 경로 좌표 없음');
-- 새 초대의 취소와 차단을 검증합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
select public.group_action(null,'create') as next_group \gset
select public.group_action(:'next_group','invite','00000000-0000-0000-0000-000000000112');
select public.group_action(:'next_group','cancel_invite','00000000-0000-0000-0000-000000000112');
select public.group_action(:'next_group','invite','00000000-0000-0000-0000-000000000113');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''accept'')',:'next_group'),'P0001'),'취소한 초대 수락 금지');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
select public.change_my_block('00000000-0000-0000-0000-000000000113',true);
select pg_temp.assert_true((select e->>'state'='cancelled' from jsonb_array_elements(public.group_dashboard()->'groups')e where e->>'id'=:'next_group'),'공통 그룹 차단 즉시 취소');
reset role;
update runspot_private.running_groups set expires_at=now()-interval '1 second',state='lobby' where id=:'next_group';
set local role authenticated;
select pg_temp.assert_true((select e->>'state'='expired' from jsonb_array_elements(public.group_dashboard()->'groups')e where e->>'id'=:'next_group'),'서버 시각으로 만료 처리');
select pg_temp.assert_true(pg_temp.fails(format('select public.group_action(%L,''ready'')',:'next_group'),'P0001'),'만료 그룹 준비 금지');
rollback;
