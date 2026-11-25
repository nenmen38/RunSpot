\set ON_ERROR_STOP on
begin;
create function pg_temp.check_char(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000a51','char51@example.com',now());
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000a51',1000,'테스트');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000a51',true);
select public.my_wallet() as w \gset
select pg_temp.check_char((:'w'::jsonb->'cosmetic_prices'->>'char_shoes_carbon')::int=450
  and (:'w'::jsonb->'cosmetic_prices'->>'char_headband_red')::int=100,'캐릭터 아이템이 상점 목록과 가격에 있음');
select public.buy_cosmetic('char_cap_blue',150) as w \gset
select pg_temp.check_char((:'w'::jsonb->>'coins')::int=850 and :'w'::jsonb->'cosmetics'->'owned' ? 'char_cap_blue','캐릭터 모자 구매');
select public.equip_cosmetic('char_head','char_cap_blue') as w \gset
select pg_temp.check_char(:'w'::jsonb->'cosmetics'->'equipped'->>'char_head'='char_cap_blue','모자 착용');
select pg_temp.check_char(pg_temp.fails($q$select public.equip_cosmetic('char_shoes','char_cap_blue')$q$,'22023'),'다른 칸에는 착용 못 함');
select pg_temp.check_char(pg_temp.fails($q$select public.equip_cosmetic('char_shoes','char_shoes_red')$q$,'P0001'),'안 산 아이템은 착용 못 함');
select public.equip_cosmetic('char_head',null) as w \gset
select pg_temp.check_char(not (:'w'::jsonb->'cosmetics'->'equipped' ? 'char_head'),'모자 벗기');
-- 기존 꾸미기도 그대로 착용됩니다.
select public.buy_cosmetic('route_neon',150);
select pg_temp.check_char(public.equip_cosmetic('route','route_neon')->'cosmetics'->'equipped'->>'route'='route_neon','기존 경로 색 착용 유지');
rollback;
