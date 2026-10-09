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
set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.claim_environment_refresh('weather:test','0900')$q$,'42501'),'비로그인 공동 갱신 차단');
reset role;
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select public.reserve_environment_attempt('air','dust:test',gen_random_uuid())$q$,'42501'),'앱 예산 예약 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.complete_environment_refresh('weather:test',gen_random_uuid(),'{}',3600,null)$q$,'42501'),'앱 캐시 오염 차단');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.environment_budgets','42501'),'앱 예산 원본 접근 차단');
reset role;
update runspot_private.environment_budgets set max_requests=2 where provider='air';
create temp table claims(id integer primary key, result jsonb);
grant all on claims to service_role;
set local role service_role;
insert into claims values(1,public.claim_environment_refresh('weather:test','0900'));
select pg_temp.assert_true((select result->>'state'='owner' from claims where id=1),'최초 갱신 권한');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','0900')->>'state'='busy','중복 갱신 차단');
select pg_temp.assert_true(public.reserve_environment_attempt('air','weather:test',(select (result->>'token')::uuid from claims where id=1))='allowed','첫 외부 호출 예산 예약');
select pg_temp.assert_true(public.reserve_environment_attempt('air','weather:test',(select (result->>'token')::uuid from claims where id=1))='allowed','페이지 요청 추가 예약');
select pg_temp.assert_true(public.reserve_environment_attempt('air','weather:test',(select (result->>'token')::uuid from claims where id=1))='quota_exhausted','API 공동 한도 차단');
select pg_temp.assert_true(public.complete_environment_refresh('weather:test',(select (result->>'token')::uuid from claims where id=1),'{"temperature":20}',86400,null),'정상 갱신 저장');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','0900')->>'state'='fresh','동일 발표 자료 공동 재사용');
insert into claims values(2,public.claim_environment_refresh('weather:test','1000'));
select pg_temp.assert_true((select result->>'state'='owner' from claims where id=2),'다음 발표 갱신');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','1000')->>'state'='busy','이전 발표값을 새 발표값으로 오인하지 않음');
select pg_temp.assert_true(public.complete_environment_refresh('weather:test',(select (result->>'token')::uuid from claims where id=2),null,86400,'quota_exhausted'),'실패 상태 저장');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','1000')->>'state'='cooldown','실패 직후 반복 갱신 금지');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','1000')->'payload'='{"temperature":20}'::jsonb,'마지막 정상 관측값 보존');
select pg_temp.assert_true(public.claim_environment_refresh('weather:test','1000')->>'error'='quota_exhausted','한도 오류 유지');
reset role;
select pg_temp.assert_true((select count(*)=2 from runspot_private.environment_attempts where provider='air'),'실패해도 예약 예산을 복원하지 않음');
update runspot_private.environment_shared_cache set retry_after=now()-interval '1 second' where cache_key='weather:test';
update runspot_private.environment_attempts set reserved_at=now()-interval '24 hours 1 second' where provider='air';
set local role service_role;
insert into claims values(3,public.claim_environment_refresh('weather:test','1000'));
select pg_temp.assert_true(public.reserve_environment_attempt('air','weather:test',(select (result->>'token')::uuid from claims where id=3))='allowed','24시간 경과분만 예산에서 제외');
reset role;
update runspot_private.environment_shared_cache set lease_until=now()-interval '1 second' where cache_key='weather:test';
set local role service_role;
insert into claims values(4,public.claim_environment_refresh('weather:test','1100'));
select pg_temp.assert_true(public.reserve_environment_attempt('air','weather:test',(select (result->>'token')::uuid from claims where id=3))='refresh_superseded','만료된 갱신 권한으로 추가 호출 금지');
select pg_temp.assert_true(not public.complete_environment_refresh('weather:test',(select (result->>'token')::uuid from claims where id=3),'{"temperature":0}',86400,null),'이전 작업자의 덮어쓰기 차단');
select pg_temp.assert_true(public.complete_environment_refresh('weather:test',(select (result->>'token')::uuid from claims where id=4),'{"temperature":21}',86400,null),'새 작업자만 갱신 허용');
select pg_temp.assert_true(pg_temp.fails($q$select public.reserve_environment_attempt('unknown','weather:test',gen_random_uuid())$q$,'22023'),'알 수 없는 기관 차단');
reset role;
rollback;
\echo '공동 캐시·갱신 권한·24시간 호출 예산 테스트 통과'
