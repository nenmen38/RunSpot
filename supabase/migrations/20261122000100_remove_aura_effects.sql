-- 상점에서 오라 효과(별가루·불꽃·물결)를 없앱니다.
-- 이미 산 오라 효과는 지웁니다. 잔액은 산 기록으로 계산하므로 지우면 그만큼 코인이 자동으로 돌아옵니다.
delete from runspot_private.equipped_cosmetics where slot='aura_effect';
delete from runspot_private.owned_cosmetics where item in ('aura_sparkle','aura_flame','aura_wave');

-- 오라 효과는 더 이상 팔지 않습니다(가격이 없으면 buy_cosmetic이 거부합니다).
create or replace function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path='' as $$
  select case item
    when 'route_neon' then 400 when 'route_gold' then 600 when 'route_rainbow' then 800
    when 'title_gold' then 300 when 'title_neon' then 400 when 'title_gradient' then 500
    when 'title_crown' then 300 when 'title_fire' then 300
    when 'bubble_mint' then 200 when 'bubble_sunset' then 200 when 'bubble_night' then 200 when 'bubble_pink' then 200
  end;
$$;
notify pgrst,'reload schema';
