\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000091'),('00000000-0000-0000-0000-000000000092');
create function pg_temp.analysis() returns jsonb language sql as $$
 select '{"version":1,"windows":[[0,300000,0,300000],[360000,660000,300000,600000]],"pauses":[[300000,360000,0]],"elevation":[[0,1000,30,4]],"gps":[[1,50,2,1,12000,250,10,50]]}'::jsonb; $$;
select pg_temp.assert_true(runspot_private.valid_run_analysis(pg_temp.analysis(),2000,600,660000),'정상 분석 자료');
select pg_temp.assert_true(not runspot_private.valid_run_analysis(pg_temp.analysis()-'gps'||'{"other":[]}',2000,600,660000),'필수 항목 누락 차단');
select pg_temp.assert_true(not runspot_private.valid_run_analysis(jsonb_set(pg_temp.analysis(),'{windows}','[[0,700000,0,600000]]'),2000,600,660000),'종료 이후 시각 차단');
select pg_temp.assert_true(not runspot_private.valid_run_analysis(jsonb_set(pg_temp.analysis(),'{pauses}','[[0,100000,0]]'),2000,600,660000),'활동과 정지 중첩 차단');
select pg_temp.assert_true(not runspot_private.valid_run_analysis(jsonb_set(pg_temp.analysis(),'{elevation}','[[0,3000,30,4]]'),2000,600,660000),'전체 거리 밖 고도 차단');
select pg_temp.assert_true(not runspot_private.valid_run_analysis(jsonb_set(pg_temp.analysis(),'{windows}','[[0,660000,0,500000]]'),2000,600,660000),'활동 시간 불일치 차단');
set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.my_run_analysis('10000000-0000-0000-0000-000000000091')$q$,'42501'),'비로그인 조회 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select public.save_my_run_with_analysis('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now()-interval '49 minutes',2000,600,'[]',20,now()-interval '49 minutes','[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]','[]',pg_temp.analysis());
select public.save_my_run_with_analysis('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now()-interval '49 minutes',2000,600,'[]',20,now()-interval '49 minutes','[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]','[]',pg_temp.analysis());
select pg_temp.assert_true((select count(*)=1 from public.runs where client_run_id='10000000-0000-0000-0000-000000000091'),'재전송 한 건');
select pg_temp.assert_true((public.my_run_analysis((select id from public.runs where client_run_id='10000000-0000-0000-0000-000000000091'))->'analysis_data')=pg_temp.analysis(),'본인 자료 복원');
select pg_temp.assert_true(pg_temp.fails($q$select * from runspot_private.run_analysis_data$q$,'42501'),'비공개 표 직접 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.save_my_run_with_analysis('10000000-0000-0000-0000-000000000091',now()-interval '1 hour',now()-interval '49 minutes',2000,600,'[]',20,now()-interval '49 minutes','[{"distance_m":1000,"duration_us":300000000},{"distance_m":1000,"duration_us":300000000}]','[]',jsonb_set(pg_temp.analysis(),'{elevation}','[]'))$q$,'22023'),'기존 분석 자료 변경 차단');
reset role;
-- 본인에게 보이지 않는 기록도 식별자로 접근할 수 없습니다.
select id as saved_id from public.runs where client_run_id='10000000-0000-0000-0000-000000000091' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.my_run_analysis(%L)',:'saved_id'),'42501'),'다른 계정 조회 차단');
reset role;
delete from public.runs where id=:'saved_id';
select pg_temp.assert_true((select count(*)=0 from runspot_private.run_analysis_data),'기록 삭제 시 분석 자료 동시 삭제');
rollback;
