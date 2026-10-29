\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return true; end; $$;
-- 한국 시각 접수 시작·마감 시각과 조기 마감, 정보 부족을 구분합니다.
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","endDate":"2027-01-03"}', '2027-02-01','2026-12-31T14:59:59Z')='upcoming','접수 시작 직전');
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","endDate":"2027-01-03"}', '2027-02-01','2026-12-31T15:00:00Z')='open','한국 자정 시작');
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","endDate":"2027-01-03"}', '2027-02-01','2027-01-03T14:59:59Z')='open','마감일 마지막 초');
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","endDate":"2027-01-03"}', '2027-02-01','2027-01-03T15:00:00Z')='closed','마감일 이후');
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","startTime":"10:00","endDate":"2027-01-03","endTime":"18:00"}', '2027-02-01','2027-01-01T00:59:59Z')='upcoming','접수 시작 시간');
select pg_temp.assert_true(runspot_private.marathon_status('{"startDate":"2027-01-01","endDate":"2027-01-03","status":"접수마감"}', '2027-02-01','2027-01-01T15:00:00Z')='closed','조기 마감');
select pg_temp.assert_true(runspot_private.marathon_status('{}','2027-02-01','2027-01-01T15:00:00Z')='unknown','접수 미정');
select pg_temp.assert_true(runspot_private.marathon_status('{"status":"접수중"}','2027-02-01','2027-02-02T15:00:00Z')='closed','대회 종료 뒤 접수중 표시 금지');

select runspot_private.import_marathons(jsonb_build_object('success',true,'count',2,'data',jsonb_build_array(
 jsonb_build_object('id','one','name','대회 하나','event',jsonb_build_object('startDate',(current_date+10)::text),'registration','{}'::jsonb),
 jsonb_build_object('id','two','name','대회 둘','event',jsonb_build_object('startDate',(current_date+20)::text),'registration','{}'::jsonb))));
select runspot_private.import_marathons(jsonb_build_object('success',true,'count',1,'data',jsonb_build_array(
 jsonb_build_object('id','one','name','수정 대회','event',jsonb_build_object('startDate',(current_date+11)::text),'registration','{}'::jsonb))));
select pg_temp.assert_true((select count(*)=2 from runspot_private.marathon_catalog),'재동기화 중복 방지');
select pg_temp.assert_true((select data->>'name'='수정 대회' from runspot_private.marathon_catalog where id='one'),'원본 수정 반영');
select pg_temp.assert_true((select not available from runspot_private.marathon_catalog where id='two'),'제공이 중단된 대회 숨김');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.import_marathons('{"success":true,"count":0,"data":[]}')$q$),'비정상 빈 응답 거부');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.import_marathons('{"success":true,"count":1,"data":[{"id":"one","name":"변조","event":{"startDate":"2027-02-30"}}]}')$q$),'잘못된 날짜 거부');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.import_marathons('{"success":true,"count":1,"data":[{"id":"one","name":"부분 응답","event":{"startDate":"2027-03-01"}}],"meta":{"nextCursor":"next"}}')$q$),'부분 응답 거부');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.import_marathons('{"success":true,"count":2,"data":[{"id":"one","name":"중복","event":{"startDate":"2027-03-01"}},{"id":"one","name":"중복","event":{"startDate":"2027-03-01"}}]}')$q$),'동일 응답 중복 ID 거부');
select pg_temp.assert_true((select data->>'name'='수정 대회' from runspot_private.marathon_catalog where id='one'),'실패 시 정상 자료 보존');
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000891','marathon@example.com',now());
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.marathon_events()'),'비로그인 조회 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000891',true);
select pg_temp.assert_true(jsonb_array_length(public.marathon_events()->'events')=1,'일반 사용자 정상 조회');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.marathon_catalog'),'원본 직접 조회 거부');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.import_marathons('{}')$q$),'사용자 임의 동기화 거부');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000891';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.marathon_events()'),'정지 계정 거부');
rollback;
