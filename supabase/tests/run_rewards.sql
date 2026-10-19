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

-- 레벨 구간: Lv.1→2 100XP, Lv.2→3 150XP, Lv.3→4 200XP
select pg_temp.assert_true(runspot_private.level_for_xp(0)=1,'0XP는 Lv.1');
select pg_temp.assert_true(runspot_private.level_for_xp(99)=1,'99XP는 Lv.1');
select pg_temp.assert_true(runspot_private.level_for_xp(100)=2,'100XP는 Lv.2');
select pg_temp.assert_true(runspot_private.level_for_xp(250)=3,'250XP는 Lv.3');
select pg_temp.assert_true(runspot_private.progress_for_xp(260)=
  '{"total_xp":260,"level":3,"level_xp":10,"next_level_xp":200}'::jsonb,'레벨 내 진행도');
select pg_temp.assert_true(runspot_private.level_for_xp(2147483647)=99,'최대 레벨');
select pg_temp.assert_true((runspot_private.progress_for_xp(2147483647)->'next_level_xp')='null'::jsonb,'최대 레벨은 다음 목표 없음');

set local role anon;
select pg_temp.assert_true(pg_temp.fails($q$select public.my_progress()$q$,'42501'),'비로그인 진행도 조회 차단');
reset role;
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.level_for_xp(1)$q$,'42501'),'내부 계산 함수 직접 실행 차단');
select pg_temp.assert_true(pg_temp.fails($q$select * from runspot_private.run_rewards$q$,'42501'),'보상 테이블 직접 조회 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select pg_temp.assert_true(public.my_progress()=
  '{"total_xp":0,"level":1,"level_xp":0,"next_level_xp":100}'::jsonb,'첫 진행도');

-- 5km: 10 + 50 = 60XP
select public.save_my_run('20000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),5000,1500);
create temp table ids as select id, client_run_id from public.runs;
grant select on ids to authenticated;
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000001') @>
  '{"status":"ready","xp":60,"reason":null,"level_before":1,"level_after":1,"progress":{"total_xp":60,"level":1}}'::jsonb,'5km 보상');

-- 재전송은 보상을 다시 지급하지 않습니다.
select public.save_my_run('20000000-0000-0000-0000-000000000001',now()-interval '30 minutes',now(),5000,1500);
select pg_temp.assert_true((public.my_progress()->>'total_xp')::int=60,'재전송 중복 보상 방지');

-- 6km: 10 + 60 = 70XP, 누적 130XP로 Lv.2
select public.save_my_run('20000000-0000-0000-0000-000000000002',now()-interval '40 minutes',now(),6000,1800);
insert into ids select id, client_run_id from public.runs where client_run_id='20000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000002') @>
  '{"xp":70,"level_before":1,"level_after":2,"progress":{"total_xp":130,"level":2,"level_xp":30,"next_level_xp":150}}'::jsonb,'레벨 상승');

-- 짧은 기록과 비현실적 속도는 저장하되 보상하지 않습니다.
select public.save_my_run('20000000-0000-0000-0000-000000000003',now()-interval '1 minute',now(),200,60);
select public.save_my_run('20000000-0000-0000-0000-000000000004',now()-interval '10 minutes',now(),10000,600);
insert into ids select id, client_run_id from public.runs where client_run_id in
  ('20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000004');
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000003') @> '{"xp":0,"reason":"too_short"}'::jsonb,'짧은 기록 무보상');
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000004') @> '{"xp":0,"reason":"too_fast"}'::jsonb,'비현실적 속도 무보상');

-- 오래된 기록은 늦게 전송하면 보상하지 않습니다.
select public.save_my_run('20000000-0000-0000-0000-000000000005',now()-interval '8 days 1 hour',now()-interval '8 days',5000,1500);
insert into ids select id, client_run_id from public.runs where client_run_id='20000000-0000-0000-0000-000000000005';
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000005') @> '{"xp":0,"reason":"late_sync"}'::jsonb,'오래된 기록 무보상');

-- 기록당 최대 300XP, 하루 최대 500XP
select public.save_my_run('20000000-0000-0000-0000-000000000006',now()-interval '5 hours',now()-interval '1 hour',40000,14000);
select public.save_my_run('20000000-0000-0000-0000-000000000007',now()-interval '50 minutes',now()-interval '1 minute',10000,2900);
insert into ids select id, client_run_id from public.runs where client_run_id in
  ('20000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000007');
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000006') @> '{"xp":300,"reason":null}'::jsonb,'기록당 최대 보상');
select pg_temp.assert_true((select (public.my_run_reward(id)->>'xp')::int <= 110 from ids
  where client_run_id='20000000-0000-0000-0000-000000000007'),'일일 보상 한도');
reset role;
-- 실행 시각이 자정 직후여도 날짜별 합계는 500XP를 넘지 않습니다.
select pg_temp.assert_true((select max(day_xp) <= 500 from (
  select sum(w.xp) as day_xp from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
  where w.user_id='00000000-0000-0000-0000-000000000091'
  group by (r.ended_at at time zone 'Asia/Seoul')::date) d),'날짜별 일일 한도');
select pg_temp.assert_true((select reason='daily_limit' and xp=70 from runspot_private.run_rewards w
  join public.runs r on r.id=w.run_id where r.client_run_id='20000000-0000-0000-0000-000000000007')
  or (select (r.ended_at at time zone 'Asia/Seoul')::date <> (now() at time zone 'Asia/Seoul')::date
  from public.runs r where r.client_run_id='20000000-0000-0000-0000-000000000006'),'한도 초과분 차감');
set local role authenticated;

-- 타인 기록과 없는 기록은 같은 응답입니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select pg_temp.assert_true((select public.my_run_reward(id) from ids
  where client_run_id='20000000-0000-0000-0000-000000000001') @> '{"status":"unavailable"}'::jsonb,'타인 보상 조회 차단');
select pg_temp.assert_true((public.my_progress()->>'total_xp')::int=0,'계정별 진행도 분리');
select pg_temp.assert_true(pg_temp.fails($q$select runspot_private.award_run_reward()$q$,'42501'),'보상 함수 직접 실행 차단');

reset role;
update runspot_private.account_controls set status='suspended' where user_id='00000000-0000-0000-0000-000000000092';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails($q$select public.my_progress()$q$,'42501'),'정지 계정 차단');
reset role;
rollback;
\echo '러닝 보상·레벨 계산 및 권한 테스트 통과'
