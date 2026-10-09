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
 ('00000000-0000-0000-0000-000000000091'),
 ('00000000-0000-0000-0000-000000000092');
set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.my_run_route('10000000-0000-0000-0000-000000000001')$q$,'42501'),'비로그인 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000001',now()-interval '1 hour',now(),100,60,'[]')$q$,'42501'),'비로그인 저장 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select pg_temp.assert_true(pg_temp.fails($q$select * from runspot_private.measured_run_routes$q$,'42501'),'원본 직접 조회 차단');
-- 전화번호 미인증 계정도 본인 전용 경로를 보관할 수 있습니다.
select public.save_my_run_with_route('10000000-0000-0000-0000-000000000001',now()-interval '1 hour',now(),100,60,
 '[[[37.5665123456,126.978],[37.567,126.979]],[[37.57,126.98]]]');
select public.save_my_run_with_route('10000000-0000-0000-0000-000000000001',now()-interval '1 hour',now(),100,60,
 '[[[37.5665123456,126.978],[37.567,126.979]],[[37.57,126.98]]]');
select pg_temp.assert_true((select count(*)=1 from public.runs),'중복 재전송 방지');
select pg_temp.assert_true((select public.my_run_route(id)='[[[37.5665123456,126.978],[37.567,126.979]],[[37.57,126.98]]]'::jsonb from public.runs),'좌표 정밀도와 단절 구간 보존');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000001',now()-interval '1 hour',now(),100,60,'[]')$q$,'22023'),'같은 기록의 다른 경로 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[[91,126]]]')$q$,'22023'),'위도 범위 검사');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[[37,181]]]')$q$,'22023'),'경도 범위 검사');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[["37",126]]]')$q$,'22023'),'문자열 좌표 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[[37,null]]]')$q$,'22023'),'빈 좌표 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[[37]]]')$q$,'22023'),'잘못된 좌표 차원 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[[]]')$q$,'22023'),'빈 구간 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,'[{}]')$q$,'22023'),'잘못된 구간 형태 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,null)$q$,'22023'),'누락된 경로 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,
 (select jsonb_agg('[[37,126]]'::jsonb) from generate_series(1,50001)))$q$,'22023'),'구간 수 상한 검사');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 hour',now(),100,60,
 jsonb_build_array((select jsonb_agg('[37,126]'::jsonb) from generate_series(1,500001))))$q$,'22023'),'좌표 수 상한 검사');
select pg_temp.assert_true((select count(*)=1 from public.runs),'잘못된 경로는 기록만 저장하지 않음');
select public.save_my_run('10000000-0000-0000-0000-000000000002',now()-interval '1 minute',now(),0,0);
select pg_temp.assert_true((select public.my_run_route(id)='[]'::jsonb from public.runs where client_run_id='10000000-0000-0000-0000-000000000002'),'기존 기록 경로 없음 호환');
select public.save_my_run_with_route('10000000-0000-0000-0000-000000000002',now()-interval '1 minute',now(),0,0,'[]');
select pg_temp.assert_true(pg_temp.fails($q$select public.my_run_route('ffffffff-ffff-ffff-ffff-ffffffffffff')$q$,'42501'),'미존재 기록도 동일하게 차단');
reset role;
select pg_temp.assert_true((select sample_count=3 from runspot_private.measured_run_routes where sample_count>0),'좌표 수 기록');
-- 실제 관계가 있어도 원본 경로는 다른 계정에 공개하지 않습니다.
insert into public.friendships(user_low,user_high,requested_by,status)
values('00000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000092','00000000-0000-0000-0000-000000000091','accepted');
select set_config('route_test.run_id',(select id::text from public.runs where client_run_id='10000000-0000-0000-0000-000000000001'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.my_run_route(%L::uuid)',current_setting('route_test.run_id')),'42501'),'친구의 원본 경로 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$delete from runspot_private.measured_run_routes$q$,'42501'),'직접 경로 삭제 차단');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000091';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.my_run_route(%L::uuid)',current_setting('route_test.run_id')),'42501'),'정지 계정 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_route('10000000-0000-0000-0000-000000000003',now()-interval '1 minute',now(),0,0,'[]')$q$,'42501'),'정지 계정 저장 차단');
reset role;
delete from public.runs where client_run_id='10000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=1 from runspot_private.measured_run_routes),'기록 삭제 시 경로 함께 삭제');
rollback;
\echo '개인 러닝 경로 저장 및 권한 테스트 통과'
