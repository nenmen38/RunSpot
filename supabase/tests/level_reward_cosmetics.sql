\set ON_ERROR_STOP on
begin;
create function pg_temp.check_lv(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000f11','lv11@example.com',now());
-- 레벨 5(누적 700XP)가 되도록 기록 3개에 XP를 나눠 줍니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000f11',gen_random_uuid(),now()-(g*interval '2 days')-interval '1 hour',now()-(g*interval '2 days'),5000,1800,'verified'
from generate_series(1,3) g;
select pg_temp.check_lv(not exists(select 1 from runspot_private.owned_cosmetics where user_id='00000000-0000-0000-0000-000000000f11' and item='char_headband_gold'),'레벨 5 전에는 없음');
update runspot_private.run_rewards set xp=case when xp>=0 then 240 end where user_id='00000000-0000-0000-0000-000000000f11';
select pg_temp.check_lv(runspot_private.user_level('00000000-0000-0000-0000-000000000f11')=5,'레벨 5');
select pg_temp.check_lv(exists(select 1 from runspot_private.owned_cosmetics where user_id='00000000-0000-0000-0000-000000000f11' and item='char_headband_gold' and coins=0),'레벨 5 선물');
select pg_temp.check_lv(not exists(select 1 from runspot_private.owned_cosmetics where user_id='00000000-0000-0000-0000-000000000f11' and item='char_shoes_rainbow'),'레벨 10 보상은 아직');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000f11',true);
select public.my_wallet() as w \gset
select pg_temp.check_lv(:'w'::jsonb->'cosmetics'->'owned' ? 'char_headband_gold','지갑에 보유');
select pg_temp.check_lv((:'w'::jsonb->'level_cosmetics'->>'char_singlet_gold')::int=20,'레벨 보상 목록');
select pg_temp.check_lv(not (:'w'::jsonb->'cosmetic_prices' ? 'char_headband_gold'),'판매 목록에는 없음');
select pg_temp.check_lv(not exists(select 1 from jsonb_array_elements(:'w'::jsonb->'transactions') t where (t->>'coins')::int=0),'0코인 내역 없음');
select pg_temp.check_lv(public.equip_cosmetic('char_head','char_headband_gold')->'cosmetics'->'equipped'->>'char_head'='char_headband_gold','선물 착용');
select pg_temp.check_lv(pg_temp.fails($q$select public.buy_cosmetic('char_shoes_rainbow',null)$q$,'22023'),'코인으로는 못 삼');
rollback;
