\set ON_ERROR_STOP on
begin;
create function pg_temp.check_mh(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000ab1','mh1@example.com',now());
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000ab1',1000,'테스트');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000ab1',true);
select public.my_wallet() as w \gset
select pg_temp.check_mh((:'w'::jsonb->'cosmetic_prices'->>'char_hair_short')::int=200
  and (:'w'::jsonb->'cosmetic_prices'->>'char_hair_dandy')::int=200
  and (:'w'::jsonb->'cosmetic_prices'->>'char_hair_spiky')::int=250,'남자 헤어스타일 3종이 판매 목록과 가격에 있음');
-- 기존 판매 목록은 그대로 남습니다.
select pg_temp.check_mh((:'w'::jsonb->'cosmetic_prices'->>'char_hair_curly')::int=250
  and (:'w'::jsonb->'cosmetic_prices'->>'route_neon')::int=150
  and (:'w'::jsonb->'cosmetic_prices'->>'char_pet_bunny')::int=450
  and not (:'w'::jsonb->'cosmetic_prices' ? 'char_cap_santa'),'기존 판매 목록 유지');
select pg_temp.check_mh(jsonb_typeof(:'w'::jsonb->'cosmetic_prices')='object'
  and (select count(*) from jsonb_object_keys(:'w'::jsonb->'cosmetic_prices'))=54,'판매 목록 54종');
select public.buy_cosmetic('char_hair_dandy',200);
select public.buy_cosmetic('char_hair_spiky',250);
select pg_temp.check_mh(public.equip_cosmetic('char_hair','char_hair_dandy')->'cosmetics'->'equipped'->>'char_hair'='char_hair_dandy','댄디컷 착용');
select pg_temp.check_mh(public.equip_cosmetic('char_hair','char_hair_spiky')->'cosmetics'->'equipped'->>'char_hair'='char_hair_spiky','같은 칸이라 삐죽머리로 바뀜');
select pg_temp.check_mh((public.my_wallet()->>'coins')::int=1000-200-250,'코인 계산');
rollback;
