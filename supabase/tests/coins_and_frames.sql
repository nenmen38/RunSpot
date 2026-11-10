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
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((select (w->>'coins')::int=0 and (w->>'level')::int=1
  and (w->>'next_reward_level')::int=2 and (w->>'next_reward_coins')::int=10
  and (w->'prices'->>'basic')::int=300 and (w->'prices'->>'aura')::int=1400
  and w->'owned'='[]'::jsonb and w->'equipped'='null'::jsonb and w->>'color'='#3182F6'
  from (select public.my_wallet() w) x),'처음 지갑');
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''basic'')','P0001'),'코인 부족 구매 거부');
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''gold'')','22023'),'없는 테두리 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.coin_grants','42501'),'지급 원본 접근 거부');
select pg_temp.assert_true(pg_temp.fails('insert into runspot_private.owned_frames(user_id,frame,coins) values(''00000000-0000-0000-0000-000000000201'',''aura'',0)','42501'),'직접 소유 등록 거부');

-- 운영자 지급 뒤 기본 테두리를 사고, 다시 사도 코인이 두 번 빠지지 않습니다.
reset role;
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000201',1000,'테스트 지급');
set local role authenticated;
select pg_temp.assert_true((public.buy_frame('basic')->>'coins')::int=700,'기본 테두리 구매');
select pg_temp.assert_true((public.buy_frame('basic')->>'coins')::int=700
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
select pg_temp.assert_true(public.record_coin_purchase('t1',:'customer','coins_16500',now(),'SANDBOX'),'결제 기록');
select pg_temp.assert_true(public.record_coin_purchase('t1',:'customer','coins_16500',now(),'SANDBOX'),'같은 거래 재전송');
select pg_temp.assert_true(not public.record_coin_purchase('t2',:'customer','coins_999',now(),'SANDBOX'),'없는 상품 무시');
select pg_temp.assert_true(not public.record_coin_purchase('t3',gen_random_uuid(),'coins_1100',now(),'SANDBOX'),'모르는 결제 계정 무시');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((public.my_wallet()->>'coins')::int=2350,'결제 코인 한 번 반영');
select pg_temp.assert_true((select w->'owned'='["aura", "basic"]'::jsonb and (w->>'coins')::int=950
  from (select public.buy_frame('aura') w) x),'오라 테두리 구매');
select pg_temp.assert_true(public.set_frame('aura','#EF4444')->>'equipped'='aura','오라 착용');

-- 다른 사람의 지갑과 테두리는 섞이지 않습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000202',true);
select pg_temp.assert_true((select (w->>'coins')::int=0 and w->'owned'='[]'::jsonb
  from (select public.my_wallet() w) x),'계정별 지갑');

-- 환불되면 코인을 빼고, 잔액이 모자라면 새 구매를 막습니다.
reset role;
set local role service_role;
select pg_temp.assert_true(public.refund_coin_purchase('t1'),'환불 기록');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select pg_temp.assert_true((public.my_wallet()->>'coins')::int=-700,'환불 후 잔액');
reset role;
delete from runspot_private.owned_frames where user_id='00000000-0000-0000-0000-000000000201' and frame='basic';
set local role authenticated;
select pg_temp.assert_true(pg_temp.fails('select public.buy_frame(''basic'')','P0001'),'음수 잔액 구매 거부');
rollback;
