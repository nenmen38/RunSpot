\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000201','coin201@example.com',now()),
 ('00000000-0000-0000-0000-000000000202','coin202@example.com',now());
update public.profiles set nickname='코인검증'||right(id::text,3) where id::text like '%00000000020_';

-- 레벨마다 10코인, 5의 배수 레벨에는 50코인을 더 줍니다.
select pg_temp.assert_true(runspot_private.level_coins(1)=0 and runspot_private.level_coins(2)=10
  and runspot_private.level_coins(5)=90 and runspot_private.level_coins(10)=190
  and runspot_private.level_coins(50)=990,'레벨 보상 코인');
select pg_temp.assert_true(runspot_private.coin_pack_coins('coins_1100')=100
  and runspot_private.coin_pack_coins('coins_49900')=5300 and runspot_private.coin_pack_coins('coins_999') is null,'코인 묶음');

set local role anon;
select pg_temp.assert_true(pg_temp.fails('select public.my_wallet()','42501'),'비로그인 지갑 거부');
select pg_temp.assert_true(pg_temp.fails('select public.claim_weekly_coin_quest(''single_3k'')','42501'),'비로그인 수령 거부');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((select (w->>'coins')::int=0 and (w->>'level')::int=1
  and (w->>'next_reward_level')::int=2 and (w->>'next_reward_coins')::int=10
  and (w->'prices'->>'basic')::int=200 and (w->'prices'->>'aura')::int=700
  and w->'owned'='[]'::jsonb and w->'equipped'='null'::jsonb and w->>'color'='#3182F6'
  from (select public.my_wallet() w) x),'처음 지갑');
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''basic'')','P0001'),'코인 부족 구매 거부');
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''gold'')','22023'),'없는 테두리 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.coin_grants','42501'),'지급 원본 접근 거부');
select pg_temp.assert_true(pg_temp.fails('insert into runspot_private.owned_frames(user_id,frame,coins) values(''00000000-0000-0000-0000-000000000201'',''aura'',0)','42501'),'직접 소유 등록 거부');

-- 운영자 지급 뒤 기본 테두리를 사고, 다시 사도 코인이 두 번 빠지지 않습니다.
reset role;
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000201',850,'테스트 지급');
set local role authenticated;
select pg_temp.assert_true((public.buy_frame('basic')->>'coins')::int=650,'기본 테두리 구매');
select pg_temp.assert_true((public.buy_frame('basic')->>'coins')::int=650
  and public.my_wallet()->'owned'='["basic"]'::jsonb,'중복 구매 방지');
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''aura'')','P0001'),'오라 코인 부족');

-- 가진 테두리만 착용하고 색은 자유롭게 바꿉니다.
select pg_temp.assert_true(pg_temp.fails('select public.set_frame(''aura'',''#FF0000'')','42501'),'없는 테두리 착용 거부');
select pg_temp.assert_true(pg_temp.fails('select public.set_frame(''basic'',''red'')','22023'),'잘못된 색 거부');
select pg_temp.assert_true((select w->>'equipped'='basic' and w->>'color'='#12AB9F'
  from (select public.set_frame('basic',' #12ab9f ') w) x),'착용과 색 변경');
select pg_temp.assert_true((select w->'equipped'='null'::jsonb and w->>'color'='#12AB9F'
  from (select public.set_frame(null,'#12AB9F') w) x),'해제해도 색 유지');

-- 웹훅은 서버 키로만 코인을 기록하고 같은 거래는 한 번만 반영합니다.
select public.cosmetic_customer() as customer \gset
select pg_temp.assert_true(pg_temp.fails(format('select public.record_coin_purchase(''t1'',%L,''coins_16500'',now(),''SANDBOX'')',:'customer'),'42501'),'사용자 결제 기록 거부');
reset role;
set local role service_role;
select pg_temp.assert_true(public.record_coin_purchase('t1',:'customer','coins_16500',now(),'PRODUCTION'),'결제 기록');
select pg_temp.assert_true(public.record_coin_purchase('t1',:'customer','coins_16500',now(),'PRODUCTION'),'같은 거래 재전송');
select pg_temp.assert_true(not public.record_coin_purchase('t2',:'customer','coins_999',now(),'PRODUCTION'),'없는 상품 무시');
select pg_temp.assert_true(not public.record_coin_purchase('t3',gen_random_uuid(),'coins_1100',now(),'PRODUCTION'),'모르는 결제 계정 무시');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((public.my_wallet()->>'coins')::int=2300,'결제 코인 한 번 반영');
select pg_temp.assert_true((select w->'owned'='["aura", "basic"]'::jsonb and (w->>'coins')::int=1600
  from (select public.buy_frame('aura') w) x),'오라 테두리 구매');
select pg_temp.assert_true(public.set_frame('aura','#EF4444')->>'equipped'='aura','오라 착용');

-- 다른 사람의 지갑과 테두리는 섞이지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000202',true);
select pg_temp.assert_true((select (w->>'coins')::int=0 and w->'owned'='[]'::jsonb
  from (select public.my_wallet() w) x),'계정별 지갑');

-- 환불되면 코인을 빼고, 잔액이 모자라면 새 구매를 막습니다.
reset role;
set local role service_role;
select pg_temp.assert_true(public.refund_coin_purchase('t1','PRODUCTION'),'환불 기록');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((public.my_wallet()->>'coins')::int=-50,'환불 후 잔액');
reset role;
delete from runspot_private.owned_frames where user_id='00000000-0000-0000-0000-000000000201' and frame='basic';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''basic'')','P0001'),'음수 잔액 구매 거부');
-- 테스트·누락 환경과 순서가 바뀐 환불은 운영 코인 잔액을 늘리지 않습니다.
reset role;
set local role service_role;
select pg_temp.assert_true(not public.record_coin_purchase('test-env',:'customer','coins_1100',now(),'SANDBOX'),'운영에서 테스트 결제 제외');
select pg_temp.assert_true(not public.record_coin_purchase('no-env',:'customer','coins_1100',now(),null),'환경 누락 거부');
select pg_temp.assert_true(not public.refund_coin_purchase('t1',null),'환경 누락 환불 거부');
select pg_temp.assert_true(public.refund_coin_purchase('early-refund','PRODUCTION'),'선행 환불 기록');
select pg_temp.assert_true(public.record_coin_purchase('early-refund',:'customer','coins_5500_v2',now(),'PRODUCTION'),'환불 뒤 구매 알림 수신');
select pg_temp.assert_true(public.record_coin_purchase('early-refund',:'customer','coins_5500_v2',now(),'PRODUCTION'),'환불 거래 재전송');
reset role;
set local role authenticated;
select pg_temp.assert_true(public.my_coin_purchase_status('early-refund') @> '{"state":"refunded","coins":500}','같은 거래 환불 확인');
select pg_temp.assert_true(not exists (
  select 1 from jsonb_array_elements(public.my_wallet()->'transactions') e
  where e->>'kind'='charge' and (e->>'coins')::integer=100
),'테스트·누락 충전이 거래 내역에 없어야 함');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000202',true);
select pg_temp.assert_true(public.my_coin_purchase_status('early-refund')->>'state'='pending','타인 거래 비공개');

-- 한국 시간 기준 서로 다른 날짜의 적격 러닝만 진행률에 반영합니다.
reset role;
update runspot_private.coin_economy_settings set quests_start_at=now()-interval '14 days';
select (date_trunc('week', (now()-interval '7 days') at time zone 'Asia/Seoul')
    + interval '6 days 18 hours') at time zone 'Asia/Seoul' as sunday \gset
select (date_trunc('week', now() at time zone 'Asia/Seoul')
    - interval '3 days' + interval '18 hours') at time zone 'Asia/Seoul' as friday \gset
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000202',gen_random_uuid(),run_day,run_day+interval '10 minutes',1000,600,'verified'
from (values (:'friday'::timestamptz), (:'friday'::timestamptz+interval '1 hour')) d(run_day);
-- 날짜를 고정한 테스트에서 지연 저장 XP 제한은 별도 테스트가 검증합니다.
update runspot_private.run_rewards set xp=20
where user_id='00000000-0000-0000-0000-000000000202';
select pg_temp.assert_true((select progress=1 from runspot_private.weekly_coin_quests(
  '00000000-0000-0000-0000-000000000202', (:'friday'::timestamptz at time zone 'Asia/Seoul')::date-4)
  where quest='two_days'),'같은 날짜 중복 제외');
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000202',gen_random_uuid(),run_day,run_day+interval '10 minutes',1000,600,'verified'
from (values (:'sunday'::timestamptz), (:'sunday'::timestamptz+interval '1 hour')) d(run_day);
update runspot_private.run_rewards set xp=20
where user_id='00000000-0000-0000-0000-000000000202';
select pg_temp.assert_true(not exists (select 1 from runspot_private.weekly_coin_rewards),'퀘스트 자동 지급 중단');
-- 전환 전에 지급된 보상을 장부에 재현합니다.
insert into runspot_private.weekly_coin_rewards(user_id,week_start,quest,coins)
values ('00000000-0000-0000-0000-000000000202',
  date_trunc('week', :'sunday'::timestamptz at time zone 'Asia/Seoul')::date,'two_days',20);
-- 검토로 레벨 보상이 달라져도 차감 사유가 장부에 남습니다.
select id as reviewed_run from public.runs
where user_id='00000000-0000-0000-0000-000000000202' order by started_at limit 1 \gset
update runspot_private.run_rewards set xp=40 where run_id=:'reviewed_run';
update public.runs set integrity_status='rejected' where id=:'reviewed_run';
select pg_temp.assert_true((select array_agg(coins order by id)=array[10,-10]
  from runspot_private.level_coin_activity
  where user_id='00000000-0000-0000-0000-000000000202'),'레벨 지급과 검토 차감 내역');
-- 지난주 보상은 유지하고, 이번 주 완료한 퀘스트만 한 번씩 수령합니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
values ('00000000-0000-0000-0000-000000000202',gen_random_uuid(),
  greatest(now()-interval '1 hour', date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'),
  now(),8000,3600,'verified');
update runspot_private.run_rewards set xp=20
where user_id='00000000-0000-0000-0000-000000000202'
  and run_id in (select id from public.runs where distance_m=8000);
select pg_temp.assert_true((select count(*)=1 from runspot_private.weekly_coin_rewards),'수령 전에는 적립하지 않음');
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.claim_weekly_coin_quest(''two_days'')','P0001'),'미완료 수령 거부');
select pg_temp.assert_true(pg_temp.fails('select public.claim_weekly_coin_quest(''invalid'')','22023'),'잘못된 퀘스트 거부');
select pg_temp.assert_true(public.claim_weekly_coin_quest('single_3k')->'weekly_quests'
  @> '[{"code":"single_3k","awarded":true}]','수령 결과를 지갑에 반영');
select public.claim_weekly_coin_quest('single_3k');
select public.claim_weekly_coin_quest('total_8k');
reset role;
select pg_temp.assert_true((select count(*)=3 and sum(coins)=30
  from runspot_private.weekly_coin_rewards),'지난주 보상 유지 및 중복 수령 방지');
rollback;
