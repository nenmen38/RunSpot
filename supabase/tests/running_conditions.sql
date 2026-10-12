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
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000093');
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.consume_environment_request()','42501'),'비로그인 요청 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.read_environment_cache('weather:60:127')$q$,'42501'),'비로그인 캐시 차단');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000093',true);
select pg_temp.assert_true(public.consume_environment_request(),'이메일 미인증 계정의 개인 환경 조회 허용');
select pg_temp.assert_true(not public.consume_environment_request(),'짧은 간격의 중복 호출 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.read_environment_cache('weather:60:127')$q$,'42501'),'앱에서 원본 캐시 조회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.write_environment_cache('weather:60:127','{}',300)$q$,'42501'),'앱에서 캐시 오염 차단');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.environment_limits','42501'),'앱에서 호출 한도 직접 수정 차단');
reset role;
update runspot_private.environment_limits set last_request=now()-interval '11 seconds',request_count=120;
set local role authenticated;
select pg_temp.assert_true(not public.consume_environment_request(),'시간당 호출 상한 차단');
reset role;
update runspot_private.environment_limits set window_start=now()-interval '1 hour';
set local role authenticated;
select pg_temp.assert_true(public.consume_environment_request(),'호출 창 만료 후 다시 허용');
reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000093';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.consume_environment_request()','42501'),'정지 계정 조회 차단');
reset role;
set local role service_role;
select public.write_environment_cache('weather:60:127','{"temperature":20}',300);
select pg_temp.assert_true(public.read_environment_cache('weather:60:127')='{"temperature":20}'::jsonb,'서버만 공개 관측 자료 캐시 사용');
select pg_temp.assert_true(pg_temp.fails($q$select public.write_environment_cache('weather:60:127','{}',0)$q$,'22023'),'캐시 보관 기간 검증');
reset role;
update runspot_private.environment_cache set expires_at=now()-interval '1 second';
set local role service_role;
select pg_temp.assert_true(public.read_environment_cache('weather:60:127') is null,'만료된 캐시 사용 금지');
reset role;
rollback;
\echo '러닝 환경 서버 권한 및 호출 제한 테스트 통과'
