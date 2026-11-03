\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return true; end; $$;
insert into auth.users(id,email,email_confirmed_at)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'ranking'||n||'@example.com',now()
from generate_series(941,948) n;
update public.profiles set nickname='랭킹'||right(id::text,3),visibility='public' where right(id::text,3)::int between 941 and 948;
update public.profiles set visibility='friends' where right(id::text,3)::int=942;
update public.profiles set visibility='private' where right(id::text,3)::int=944;
update auth.users set email_confirmed_at=null where right(id::text,3)::int=948;
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000941','00000000-0000-0000-0000-000000000942','00000000-0000-0000-0000-000000000941','accepted');
insert into runspot_private.blocks(blocker_id,blocked_id) values
 ('00000000-0000-0000-0000-000000000947','00000000-0000-0000-0000-000000000941');
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,gen_random_uuid(),now()-interval '30 minutes',now(),
 case n when 941 then 600 when 942 then 1200 else 2400 end,1200 from generate_series(941,948) n;
-- 같은 날 여러 번 달려도 꾸준함 점수는 하루 한 번만 인정합니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
values ('00000000-0000-0000-0000-000000000941',gen_random_uuid(),now()-interval '10 minutes',now(),600,180);
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,split_data)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,gen_random_uuid(),now()-interval '15 days',now()-interval '14 days',5000,
 case n when 941 then 1800 when 942 then 1500 else 1200 end,
 (select jsonb_agg(jsonb_build_object('distance_m',1000,'duration_us',case n when 941 then 360000000 when 942 then 300000000 else 240000000 end + i*0)) from generate_series(1,5) i)
from generate_series(941,943) n;
-- 기록 없는 친구도 목록에서 사라지지 않습니다.
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000941','00000000-0000-0000-0000-000000000946','00000000-0000-0000-0000-000000000941','accepted');
delete from public.runs where user_id='00000000-0000-0000-0000-000000000946';
set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.runner_ranking()'),'비로그인 랭킹 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000941',true);
select pg_temp.assert_true(pg_temp.fails('select public.runner_ranking(''wrong'',''all'')'),'잘못된 기준 거부');
select pg_temp.assert_true(jsonb_array_length(public.runner_ranking('distance','friends')->'entries')=3,'기록 없는 친구도 포함');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(public.runner_ranking('distance','friends')->'entries') e where (e->>'rank')::int=1),'같은 거리는 공동 순위');
select pg_temp.assert_true((public.runner_ranking('longest','friends')->'entries'->0->>'score')::int=1200 and (public.runner_ranking('longest','friends')->'entries'->0->>'nickname')='랭킹942','최장 거리는 합산하지 않고 단일 러닝 최대 거리');
select pg_temp.assert_true((public.runner_ranking('longest','friends')->'entries'->1->>'score')::int=600,'같은 날 여러 러닝도 개별 거리로 비교');
select pg_temp.assert_true((public.runner_ranking('consistency','friends')->'entries'->0->>'score')::int=1,'하루 여러 러닝은 하루');
select pg_temp.assert_true((public.runner_ranking('five_k','friends')->'entries'->0->>'score')::bigint=1500000000,'5km는 짧은 기록 우선이며 과거 기록도 포함');
select pg_temp.assert_true((public.runner_ranking('five_k','all')->'entries'->0->>'nickname')='랭킹943','전체 5km 순위');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.runner_ranking('distance','all')->'entries') e
 where e->>'nickname' in ('랭킹942','랭킹944','랭킹947','랭킹948')),'친구 공개·비공개·역방향 차단·미인증 제외');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.runner_ranking('distance','friends')->'entries') e
 where e->>'nickname'='랭킹946' and e->>'score'='0' and e->>'rank'='0'),'기록 없는 친구는 0km·순위 없음');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.runner_ranking('five_k','friends')->'entries') e
 where e->>'nickname'='랭킹946' and e->>'score'='0' and e->>'rank'='0'),'5km 미완주 친구도 기록 없이 표시');
rollback;
