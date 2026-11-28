-- 남자 헤어스타일 3종(짧은 머리·댄디컷 200코인, 삐죽머리 250코인)을 상점에 더합니다.
-- 판매 목록은 cosmetic_catalog() 한 곳에 모아, 다음부터는 이 함수만 고치면 지갑의 가격표에도 나옵니다.

create or replace function runspot_private.cosmetic_slot(item text)
returns text language sql immutable set search_path='' as $$
  select case
    when item in ('share_minimal','share_night') then 'share_card'
    when item in ('route_neon','route_gold','route_rainbow') then 'route'
    when item in ('title_gold','title_neon','title_gradient','title_crown','title_fire') then 'title_style'
    when item in ('aura_sparkle','aura_flame','aura_wave') then 'aura_effect'
    when item in ('bubble_mint','bubble_sunset','bubble_night','bubble_pink') then 'chat_bubble'
    when item in ('char_cap_blue','char_cap_black','char_visor_white','char_headband_red','char_headband_gold','char_cap_santa') then 'char_head'
    when item in ('char_glasses_black','char_glasses_mirror') then 'char_eyes'
    when item in ('char_singlet_orange','char_tee_mint','char_tee_navy','char_singlet_gold') then 'char_top'
    when item in ('char_shorts_black','char_shorts_blue') then 'char_bottom'
    when item in ('char_sleeves_black','char_sleeves_neon') then 'char_sleeves'
    when item in ('char_hair_bob','char_hair_ponytail','char_hair_pigtails','char_hair_bun','char_hair_curly','char_hair_short','char_hair_dandy','char_hair_spiky') then 'char_hair'
    when item in ('char_haircolor_black','char_haircolor_chestnut','char_haircolor_blonde','char_haircolor_pink','char_haircolor_sky') then 'char_haircolor'
    when item in ('char_face_wink','char_face_heart','char_face_star','char_face_happy') then 'char_face'
    when item in ('char_pet_chick','char_pet_dog','char_pet_cat','char_pet_bunny') then 'char_pet'
    when item in ('char_season_scarf','char_season_padding','char_season_raincoat') then 'char_season'
    when item in ('char_shoes_red','char_shoes_neon','char_shoes_carbon','char_shoes_rainbow') then 'char_shoes'
  end;
$$;

create or replace function runspot_private.cosmetic_price(item text)
returns integer language sql immutable set search_path = '' as $$
  select case item
    when 'share_minimal' then 100 when 'share_night' then 200
    when 'route_neon' then 150 when 'route_gold' then 300 when 'route_rainbow' then 500
    when 'title_gold' then 150 when 'title_neon' then 200 when 'title_gradient' then 250
    when 'title_crown' then 150 when 'title_fire' then 150
    when 'bubble_mint' then 100 when 'bubble_sunset' then 200 when 'bubble_night' then 150 when 'bubble_pink' then 150
    when 'char_cap_blue' then 150
    when 'char_cap_black' then 150
    when 'char_visor_white' then 200
    when 'char_headband_red' then 100
    when 'char_glasses_black' then 200
    when 'char_glasses_mirror' then 250
    when 'char_singlet_orange' then 200
    when 'char_tee_mint' then 200
    when 'char_tee_navy' then 250
    when 'char_shorts_black' then 150
    when 'char_shorts_blue' then 150
    when 'char_sleeves_black' then 150
    when 'char_sleeves_neon' then 200
    when 'char_shoes_red' then 250
    when 'char_shoes_neon' then 300
    when 'char_shoes_carbon' then 450
    when 'char_hair_bob' then 200
    when 'char_hair_ponytail' then 200
    when 'char_hair_pigtails' then 200
    when 'char_hair_bun' then 200
    when 'char_hair_curly' then 250
    when 'char_hair_short' then 200
    when 'char_hair_dandy' then 200
    when 'char_hair_spiky' then 250
    when 'char_haircolor_black' then 100
    when 'char_haircolor_chestnut' then 100
    when 'char_haircolor_blonde' then 150
    when 'char_haircolor_pink' then 200
    when 'char_haircolor_sky' then 200
    when 'char_face_wink' then 150
    when 'char_face_heart' then 200
    when 'char_face_star' then 200
    when 'char_face_happy' then 150
    when 'char_pet_chick' then 300
    when 'char_pet_dog' then 400
    when 'char_pet_cat' then 400
    when 'char_pet_bunny' then 450
    when 'char_season_scarf' then 250
    when 'char_season_padding' then 300
    when 'char_season_raincoat' then 250
  end;
$$;

create or replace function runspot_private.cosmetic_catalog()
returns text[] language sql immutable set search_path = '' as $$
  select array['route_neon','route_gold','route_rainbow','title_gold','title_neon',
        'title_gradient','title_crown','title_fire','bubble_mint','bubble_sunset','bubble_night','bubble_pink','share_minimal','share_night',
        'char_cap_blue','char_cap_black','char_visor_white','char_headband_red','char_glasses_black','char_glasses_mirror','char_singlet_orange','char_tee_mint','char_tee_navy','char_shorts_black','char_shorts_blue','char_sleeves_black','char_sleeves_neon','char_shoes_red','char_shoes_neon','char_shoes_carbon','char_hair_bob','char_hair_ponytail','char_hair_pigtails','char_hair_bun','char_hair_curly','char_hair_short','char_hair_dandy','char_hair_spiky','char_haircolor_black','char_haircolor_chestnut','char_haircolor_blonde','char_haircolor_pink','char_haircolor_sky','char_face_wink','char_face_heart','char_face_star','char_face_happy','char_pet_chick','char_pet_dog','char_pet_cat','char_pet_bunny','char_season_scarf','char_season_padding','char_season_raincoat']::text[];
$$;

create or replace function runspot_private.wallet_json(target uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with l as (select runspot_private.user_level(target) as level,
    date_trunc('week', now() at time zone 'Asia/Seoul')::date as week_start)
  select jsonb_build_object(
    'coins',runspot_private.coin_balance(target),
    'level',l.level,
    'level_coins',runspot_private.level_coins(l.level),
    'next_reward_level',case when l.level < 99 then l.level+1 end,
    'next_reward_coins',case when l.level < 99
      then runspot_private.level_coins(l.level+1)-runspot_private.level_coins(l.level) end,
    'prices',jsonb_build_object('basic',runspot_private.frame_price('basic'),
      'aura',runspot_private.frame_price('aura'),'crew_ticket',runspot_private.crew_ticket_price_for(target),
      'crew_expansion',runspot_private.crew_expansion_price()),
    'cosmetic_prices',(select jsonb_object_agg(code, runspot_private.cosmetic_price(code))
      from unnest(runspot_private.cosmetic_catalog()) as items(code)),
    'weekly_quest',jsonb_build_object(
      'days',least(2,runspot_private.weekly_coin_days(target,l.week_start)),
      'reward',20,
      'awarded',exists(select 1 from runspot_private.weekly_coin_rewards w
        where w.user_id=target and w.week_start=l.week_start and w.quest='two_days')),
    'weekly_quests',(
      select jsonb_agg(jsonb_build_object(
        'code',q.quest,'progress',least(q.progress,q.goal),'goal',q.goal,
        'reward',q.coins,'awarded',w.user_id is not null
      ) order by q.display_order)
      from runspot_private.weekly_coin_quests(target,l.week_start) q
      left join runspot_private.weekly_coin_rewards w
        on w.user_id=target and w.week_start=l.week_start and w.quest=q.quest
    ),
    'transactions',(select coalesce(jsonb_agg(to_jsonb(entry) order by entry.at desc),'[]'::jsonb)
      from (
        select * from (
          select 'charge' as kind, p.coins, p.purchased_at as at
          from runspot_private.coin_purchases p where p.user_id=target
            and p.environment=(select store_environment from runspot_private.coin_economy_settings)
          union all
          select 'refund',-p.coins,p.refunded_at
          from runspot_private.coin_purchases p where p.user_id=target and p.refunded_at is not null
            and p.environment=(select store_environment from runspot_private.coin_economy_settings)
          union all
          select 'weekly',w.coins,w.awarded_at from runspot_private.weekly_coin_rewards w where w.user_id=target
          union all
          select 'grant',g.coins,g.created_at from runspot_private.coin_grants g where g.user_id=target
          union all
          select 'level',lca.coins,lca.created_at from runspot_private.level_coin_activity lca where lca.user_id=target
          union all
          select 'item',-f.coins,f.purchased_at from runspot_private.owned_frames f where f.user_id=target
          union all
          select 'item',-c.coins,c.purchased_at from runspot_private.owned_cosmetics c where c.user_id=target and c.coins>0
          union all
          select 'item',-t.coins,t.purchased_at from runspot_private.crew_tickets t where t.user_id=target
          union all
          select 'item',-e.coins,e.purchased_at from runspot_private.crew_expansions e where e.user_id=target
        ) entries order by at desc limit 20
      ) entry),
    'owned',(select coalesce(jsonb_agg(frame order by frame),'[]'::jsonb)
      from runspot_private.owned_frames where user_id=target),
    'equipped',(select frame from runspot_private.frame_settings where user_id=target),
    'color',coalesce((select color from runspot_private.frame_settings where user_id=target),'#3182F6'),
    'crew_tickets',(select count(*) from runspot_private.crew_tickets where user_id=target and used_at is null),
    'in_crew',exists(select 1 from runspot_private.crew_members where user_id=target),
    'level_cosmetics',(select jsonb_object_agg(code, runspot_private.cosmetic_unlock_level(code))
      from unnest(array['char_headband_gold','char_shoes_rainbow','char_singlet_gold']) as items(code)),
    'cosmetics',jsonb_build_object(
      'owned',(select coalesce(jsonb_agg(item order by item),'[]'::jsonb)
        from runspot_private.owned_cosmetics where user_id=target),
      'equipped',(select coalesce(jsonb_object_agg(slot,item),'{}'::jsonb)
        from runspot_private.equipped_cosmetics where user_id=target)))
  from l;
$$;

notify pgrst,'reload schema';
