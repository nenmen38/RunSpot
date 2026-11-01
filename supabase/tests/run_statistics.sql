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
insert into auth.users(id,email,email_confirmed_at)
select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'statistics' || n || '@example.com',now() from generate_series(101,112) n;
update public.profiles set nickname='통계'||right(id::text,3),visibility='friends'
where right(id::text,3)::int between 101 and 112;
update public.profiles set visibility='private' where right(id::text,3)::int in (101,104);
update public.profiles set visibility='public' where right(id::text,3)::int in (103,111);
update auth.users set email_confirmed_at=null where right(id::text,3)::int=108;
update runspot_private.account_controls set status='suspended' where right(user_id::text,3)::int=107;
insert into public.friendships(user_low,user_high,requested_by,status)
select '00000000-0000-0000-0000-000000000101',
  ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  '00000000-0000-0000-0000-000000000101',case when n=109 then 'pending' else 'accepted' end
from generate_series(102,110) n;
insert into runspot_private.blocks(blocker_id,blocked_id) values
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000105'),
 ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000101');

-- 세션 시간대에 의존하지 않는 주간 경계를 검증합니다.
set local timezone='UTC';
create temp table week as select date_trunc('week',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as start;
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000101',gen_random_uuid(),v.ended-interval '1 hour',v.ended,v.distance,v.duration,v.status
from week w cross join lateral (values
 (w.start-interval '1 microsecond',1000,600,'pending'),
 (w.start,3000,900,'pending'),
 (now(),0,60,'pending'),
 (now(),100,0,'pending'),
 (now(),200,60,'rejected'),
 (w.start+interval '7 days',9000,900,'pending')
) v(ended,distance,duration,status);
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,gen_random_uuid(),
  w.start-interval '1 hour',w.start,case when n=102 then 3000 else 4000 end,1200
from generate_series(102,109) n cross join week w;

set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.my_run_statistics()','42501'),'비로그인 통계 차단');
select pg_temp.assert_true(pg_temp.fails('select public.friend_weekly_ranking()','42501'),'비로그인 랭킹 차단');
reset role;
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.my_run_statistics()','42501'),'빈 세션 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000101',true);
select pg_temp.assert_true(public.my_run_statistics() @>
 '{"weekly_distance_m":3300,"completed_runs":2,"pace_distance_m":4200,"pace_duration_sec":1560}'::jsonb,
 '주간 경계·누적 횟수·거리 가중 페이스·미래 기록 제외');
select pg_temp.assert_true(jsonb_array_length(public.friend_weekly_ranking()->'entries')=4,
 '본인·친구 공개·전체 공개·기록 없는 친구만 포함');
select pg_temp.assert_true(public.friend_weekly_ranking()->'entries'->0 @>
 '{"rank":1,"nickname":"통계103","distance_m":4000,"is_me":false}'::jsonb,'거리 내림차순');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.friend_weekly_ranking()->'entries') e
 where (e->>'rank')::int=2 and (e->>'distance_m')::int=3000),'보류 거리 제외 후 같은 거리는 공동 순위');
select pg_temp.assert_true(public.friend_weekly_ranking()->'entries'->3 @>
 '{"rank":4,"nickname":"통계110","distance_m":0}'::jsonb,'공동 순위 뒤 순번과 기록 없는 친구');
select pg_temp.assert_true((select count(*)=6 from public.runs),'친구 원본 기록 접근 차단 유지');
select pg_temp.assert_true(not jsonb_path_exists(public.friend_weekly_ranking(),'$.entries[*].user_id')
 and not jsonb_path_exists(public.friend_weekly_ranking(),'$.entries[*].started_at'),'집계 외 식별자와 시각 미노출');
reset role;
delete from public.friendships where user_high='00000000-0000-0000-0000-000000000102';
update public.profiles set visibility='private' where id='00000000-0000-0000-0000-000000000103';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.friend_weekly_ranking()->'entries')=2,'친구 삭제·비공개 전환 즉시 반영');
select pg_temp.assert_true(public.friend_weekly_ranking()->'entries'->0 @>
 '{"rank":1,"is_me":true,"distance_m":3000}'::jsonb,'대상 제외 후 재순위');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000112',true);
select pg_temp.assert_true(public.my_run_statistics() @>
 '{"weekly_distance_m":0,"completed_runs":0,"pace_distance_m":0,"pace_duration_sec":0}'::jsonb,'기록 없는 개인 통계');
select pg_temp.assert_true(jsonb_array_length(public.friend_weekly_ranking()->'entries')=1,'친구 없는 계정은 본인만 표시');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000108',true);
select pg_temp.assert_true((public.my_run_statistics()->>'completed_runs')::int=1,'미인증 개인 통계 허용');
select pg_temp.assert_true(public.friend_weekly_ranking() @> '{"can_interact":false,"entries":[]}'::jsonb,'미인증 소셜 조회 제한');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000107',true);
select pg_temp.assert_true(pg_temp.fails('select public.my_run_statistics()','42501'),'정지 계정 통계 차단');
select pg_temp.assert_true(pg_temp.fails('select public.friend_weekly_ranking()','42501'),'정지 계정 랭킹 차단');
reset role;
rollback;
\echo '개인 통계·친구 주간 랭킹 집계 및 권한 테스트 통과'

-- 성장 추이는 전체 기록을 집계하고 월 경계·구간 완성도·계정 격리를 지킵니다.
begin;
create function pg_temp.growth_assert(ok boolean,message text)
returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000851','growth851@example.com',now()),
 ('00000000-0000-0000-0000-000000000852','growth852@example.com',now());
create temp table growth_month as select
 date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' as start;
-- 11km 중 마지막 5km가 가장 빠르므로 첫 5km만 비교하는 오류도 검출합니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,split_data,hidden)
select '00000000-0000-0000-0000-000000000851',gen_random_uuid(),start-interval '2 hours',start,11000,3600,
 (select jsonb_agg(jsonb_build_object('distance_m',1000,'duration_us',case when n<=6 then 350000000 else 300000000 end) order by n)
 from generate_series(1,11) n),true from growth_month;
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
select '00000000-0000-0000-0000-000000000851',gen_random_uuid(),start-interval '2 hours',start-interval '1 microsecond',20000,7200 from growth_month;
-- 거리만 채운 옛 기록, 미완성 마지막 구간, 미래 기록, 반려·검토 보류를 구분합니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,split_data,integrity_status)
select '00000000-0000-0000-0000-000000000851',gen_random_uuid(),v.ended-interval '5 hours',v.ended,v.metres,v.seconds,v.splits,v.status
from growth_month m cross join lateral (values
 (m.start,4999,1499,(select jsonb_agg(jsonb_build_object('distance_m',case when n=5 then 999 else 1000 end,'duration_us',case when n=5 then 299000000 else 300000000 end)) from generate_series(1,5) n),'pending'),
 (now()+interval '1 day',50000,18000,null,'pending'),
 (m.start,40000,14400,null,'rejected'),
 (m.start,30000,1000,null,'pending')
) v(ended,metres,seconds,splits,status);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000851',true);
select pg_temp.growth_assert(jsonb_array_length(public.my_run_statistics()->'growth'->'monthly_distances')=12,'거리 없는 달도 12개월 포함');
select pg_temp.growth_assert(public.my_run_statistics()->'growth'->'monthly_distances'->11 @>
 '{"distance_m":15999,"completed_runs":2}'::jsonb,'한국 시간 월 시작과 숨김 포함, 미래·반려·보류 제외');
select pg_temp.growth_assert(public.my_run_statistics()->'growth'->'monthly_distances'->10 @>
 '{"distance_m":20000,"completed_runs":1}'::jsonb,'월 시작 직전 기록은 지난달');
select pg_temp.growth_assert(public.my_run_statistics()->'growth'->'longest_run' @> '{"distance_m":20000}'::jsonb,'구간 없는 옛 기록도 최장 거리에 포함');
select pg_temp.growth_assert(public.my_run_statistics()->'growth'->'best_5k' @> '{"duration_us":1500000000}'::jsonb,'연속 후반 5km 기록과 미완성 구간 제외');
select pg_temp.growth_assert(public.my_run_statistics()->'growth'->'best_10k' @> '{"duration_us":3250000000}'::jsonb,'연속 10km 구간 기록');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000852',true);
select pg_temp.growth_assert(public.my_run_statistics()->'growth' @>
 '{"longest_run":null,"best_5k":null,"best_10k":null}'::jsonb,'다른 계정의 최고 기록 미노출');
select pg_temp.growth_assert(not exists(select 1 from jsonb_array_elements(public.my_run_statistics()->'growth'->'monthly_distances') m
 where (m->>'distance_m')::int<>0),'빈 계정의 월별 거리 0');
reset role;
rollback;
\echo '개인 성장 추이·월 경계·최고 기록·계정 격리 테스트 통과'
