\set ON_ERROR_STOP on
begin;
create function pg_temp.check_cc(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000cc1','cc1@example.com',now());
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000cc1',3000,'테스트');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000cc1',true);
select public.my_wallet() as w \gset
select pg_temp.check_cc((:'w'::jsonb->'cosmetic_prices'->>'char_pet_bunny')::int=450
  and (:'w'::jsonb->'cosmetic_prices'->>'char_haircolor_black')::int=100
  and (:'w'::jsonb->'cosmetic_prices'->>'char_season_padding')::int=300
  and (:'w'::jsonb->'cosmetic_prices'->>'char_face_heart')::int=200
  and (:'w'::jsonb->'cosmetic_prices'->>'char_hair_curly')::int=250,'새 아이템이 상점 목록과 가격에 있음');
select pg_temp.check_cc(not (:'w'::jsonb->'cosmetic_prices' ? 'char_cap_santa'),'챌린지 보상은 판매 목록에 없음');
-- 21종을 모두 살 수 있고 칸마다 하나씩 동시에 착용합니다.
select public.buy_cosmetic('char_hair_bob',200);
select public.buy_cosmetic('char_hair_pigtails',200);
select public.buy_cosmetic('char_haircolor_pink',200);
select public.buy_cosmetic('char_face_wink',150);
select public.buy_cosmetic('char_pet_cat',400);
select public.buy_cosmetic('char_season_scarf',250);
select public.equip_cosmetic('char_hair','char_hair_bob');
select public.equip_cosmetic('char_haircolor','char_haircolor_pink');
select public.equip_cosmetic('char_face','char_face_wink');
select public.equip_cosmetic('char_pet','char_pet_cat');
select public.equip_cosmetic('char_season','char_season_scarf') as w \gset
select pg_temp.check_cc(:'w'::jsonb->'cosmetics'->'equipped'->>'char_hair'='char_hair_bob'
  and :'w'::jsonb->'cosmetics'->'equipped'->>'char_haircolor'='char_haircolor_pink'
  and :'w'::jsonb->'cosmetics'->'equipped'->>'char_pet'='char_pet_cat'
  and :'w'::jsonb->'cosmetics'->'equipped'->>'char_season'='char_season_scarf','5칸 동시 착용');
-- 같은 칸은 하나만: 양갈래로 바꾸면 단발이 빠집니다.
select public.equip_cosmetic('char_hair','char_hair_pigtails')->'cosmetics'->'equipped'->>'char_hair' as h \gset
select pg_temp.check_cc(:'h'='char_hair_pigtails','같은 칸은 하나만 착용');
select pg_temp.check_cc(pg_temp.fails($q$select public.equip_cosmetic('char_pet','char_hair_bob')$q$,'22023'),'다른 칸에는 못 입음');
select pg_temp.check_cc(pg_temp.fails($q$select public.equip_cosmetic('char_pet','char_pet_dog')$q$,'P0001'),'안 산 아이템은 못 입음');
select pg_temp.check_cc(not (public.equip_cosmetic('char_pet',null)->'cosmetics'->'equipped' ? 'char_pet'),'반려동물 벗기');
select pg_temp.check_cc((public.my_wallet()->>'coins')::int=3000-200-200-200-150-400-250,'코인 계산');
-- 기존 경로 색·캐릭터 아이템도 그대로 동작합니다.
select public.buy_cosmetic('route_neon',150);
select public.buy_cosmetic('char_cap_blue',150);
select pg_temp.check_cc(public.equip_cosmetic('char_head','char_cap_blue')->'cosmetics'->'equipped'->>'char_head'='char_cap_blue','기존 모자 착용 유지');
rollback;
