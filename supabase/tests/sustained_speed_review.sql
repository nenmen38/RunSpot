\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
-- 적도에서 초속 m만큼 북쪽으로 이동하는 재현 가능한 GPS 표본입니다.
create function pg_temp.samples(speed double precision,seconds integer,accuracy double precision default 5)
returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_array(trunc(extract(epoch from now()-interval '1 hour')*1000)+s*1000,
   speed*s/111194.92664455874,0,accuracy,0) order by s) from generate_series(0,seconds,5)s;
$$;
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(4.1666667,120),now()-interval '1 hour',now()))=0,'4분 페이스 정상 러닝');
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(10,60),now()-interval '1 hour',now()))=2,'60초 지속 고속 이동');
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(10,55),now()-interval '1 hour',now()))=0,'짧은 가속만으로 보류 금지');
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(6.5,120,0),now()-interval '1 hour',now()))=0,'속도 경계값 초과만 판정');
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(7,120,25),now()-interval '1 hour',now()))=0,'정확도 반경을 고려한 보수적 판정');
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(pg_temp.samples(10,120,50),now()-interval '1 hour',now()))=0,'낮은 정확도는 증거 제외');
-- 일시 정지, 단절, 한 번의 점프는 서로 다른 연속 구간입니다.
with points as (select case when ord>7 then jsonb_set(p,'{4}','1') else p end p,ord
 from jsonb_array_elements(pg_temp.samples(10,60)) with ordinality t(p,ord))
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion((select jsonb_agg(p order by ord) from points),now()-interval '1 hour',now()))=0,'일시 정지 전후 연결 금지');
with points as (select p,ord from jsonb_array_elements(pg_temp.samples(10,70)) with ordinality t(p,ord) where ord not in (7,8))
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion((select jsonb_agg(p order by ord) from points),now()-interval '1 hour',now()))=0,'10초 초과 위치 단절 연결 금지');
with points as (select case when ord=8 then jsonb_set(p,'{1}','80') else p end p,ord
 from jsonb_array_elements(pg_temp.samples(4,90)) with ordinality t(p,ord))
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion((select jsonb_agg(p order by ord) from points),now()-interval '1 hour',now()))=0,'단발성 GPS 점프 제외');
-- 고속 이동이 고정 30초 경계 사이에서 시작해도 직전 60초로 확인합니다.
with points as (
 select jsonb_build_array(trunc(extract(epoch from now()-interval '1 hour')*1000)+s*1000,
   (case when s<=15 then s*3 else 45+(s-15)*8 end)/111194.92664455874,0,0,0) p,s
 from generate_series(0,75,5)s)
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(
 (select jsonb_agg(p order by s) from points),now()-interval '1 hour',now()))=2,'30초 경계와 무관한 60초 고속 이동');
-- 표본 간격이 7초여도 경계는 보간합니다.
with points as (
 select jsonb_build_array(trunc(extract(epoch from now()-interval '1 hour')*1000)+s*1000,
   s*10/111194.92664455874,0,5,0) p,s from generate_series(0,63,7)s)
select pg_temp.assert_true(jsonb_array_length(runspot_private.evaluate_run_motion(
 (select jsonb_agg(p order by s) from points),now()-interval '1 hour',now()))=2,'불규칙한 표본 간격 보간');
select pg_temp.assert_true(pg_temp.fails($s$select runspot_private.evaluate_run_motion('[[1,37,127,-1,0]]',now(),now())$s$,'22023'),'측정 범위 검증');
select pg_temp.assert_true(pg_temp.fails($s$select runspot_private.evaluate_run_motion('[["x",37,127,5,0]]',now(),now())$s$,'22023'),'측정 형식 검증');

insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000091','motion91@example.com',now()),
 ('00000000-0000-0000-0000-000000000092','motion92@example.com',now());
update public.profiles set nickname='속도'||right(id::text,2) where id in ('00000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000092');
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000092','moderator');
select pg_temp.samples(10,60) as motion \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select public.save_my_run_with_motion('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]',:'motion') as saved \gset
select (:'saved'::jsonb->>'id')::uuid as held_id \gset
select pg_temp.assert_true((:'saved'::jsonb->>'review_pending')::boolean,'전체 평균이 느린 기록의 60초 차량 이동 보류');
select pg_temp.assert_true(jsonb_array_length(:'saved'::jsonb->'motion_evidence')=2,'저장 응답의 서버 계산 증거');
select pg_temp.assert_true(public.my_run_reward(:'held_id')->>'reason'='review_pending','원자적 보상 보류');
select pg_temp.assert_true((public.friend_weekly_ranking()->'entries'->0->>'distance_m')::int=0,'랭킹 보류');
select public.save_my_run_with_motion('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]',:'motion');
select pg_temp.assert_true(pg_temp.fails($s$select public.save_my_run_with_motion('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now(),2000,600,'[]',null,null,
 '[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]','[]')$s$,'22023'),'변경한 증거 재전송 차단');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.run_motion_samples','42501'),'원시 좌표 직접 조회 차단');
select pg_temp.assert_true(pg_temp.fails('update public.runs set motion_evidence=''[]''','42501'),'판정 근거 직접 변경 차단');
select pg_temp.assert_true(pg_temp.fails($s$select runspot_private.evaluate_run_motion('[]',now(),now())$s$,'42501'),'일반 사용자 내부 판정 호출 차단');
reset role;
select pg_temp.assert_true((select count(*)=1 from runspot_private.run_motion_samples where run_id=:'held_id'),'원시 측정 중복 방지');
select id as case_id from runspot_private.integrity_cases where run_id=:'held_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true((public.review_cases()->0->>'rule')='sustained_speed_over_6_5','관리자 판정 사유');
select pg_temp.assert_true(jsonb_array_length(public.review_cases()->0->'motion_evidence')=2,'관리자 시간·속도·정확도 증거');
select public.resolve_review(:'case_id','approved','실제 러닝 확인');
select public.resolve_review(:'case_id','approved','중복 승인');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select pg_temp.assert_true((public.my_run_reward(:'held_id')->>'xp')::int=30,'승인 후 한 번 지급');
reset role;
rollback;
\echo '지속 속도·GPS 오차·원자적 보류·권한 검증 통과'
