\set ON_ERROR_STOP on
begin;
create function pg_temp.check_item(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000301','item301@example.com',now()),
 ('00000000-0000-0000-0000-000000000302','item302@example.com',now()),
 ('00000000-0000-0000-0000-000000000303','item303@example.com',now());
update public.profiles set nickname='아이템검증'||right(id::text,3),visibility='public' where id::text like '%00000000030_';
insert into runspot_private.coin_grants(user_id,coins,reason) values
 ('00000000-0000-0000-0000-000000000301',3000,'테스트'),('00000000-0000-0000-0000-000000000302',100,'테스트');
-- 301: 10.2km 한 번(새벽 5시 30분 출발), 반려된 25km 한 번
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status) values
 ('00000000-0000-0000-0000-000000000301',gen_random_uuid(),'2026-11-10 20:30+00','2026-11-10 21:30+00',10200,3600,'verified'),
 ('00000000-0000-0000-0000-000000000301',gen_random_uuid(),'2026-11-12 01:00+00','2026-11-12 03:00+00',25000,7200,'rejected');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
-- 꾸미기 아이템은 사고, 가진 것만 칸에 맞게 착용합니다.
select pg_temp.check_item(pg_temp.fails('select public.equip_cosmetic(''route'',''route_gold'')','P0001'),'안 산 아이템 착용 거부');
select pg_temp.check_item((select (w->>'coins')::int=2400 and w->'cosmetics'->'owned' ? 'route_gold'
  from (select public.buy_cosmetic('route_gold') w) x),'경로 색 구매');
select pg_temp.check_item((select (w->>'coins')::int=2400 from (select public.buy_cosmetic('route_gold') w) x),'같은 아이템 다시 사지 않음');
select pg_temp.check_item(pg_temp.fails('select public.equip_cosmetic(''chat_bubble'',''route_gold'')','22023'),'다른 칸 착용 거부');
select pg_temp.check_item(pg_temp.fails('select public.buy_cosmetic(''rocket'')','22023'),'없는 아이템 거부');
select pg_temp.check_item((select w->'cosmetics'->'equipped'->>'route'='route_gold'
  from (select public.equip_cosmetic('route','route_gold') w) x),'경로 색 착용');
select public.buy_cosmetic('title_crown');
select public.buy_cosmetic('bubble_mint');
select public.equip_cosmetic('title_style','title_crown');
select public.equip_cosmetic('chat_bubble','bubble_mint');
select pg_temp.check_item((select not (w->'cosmetics'->'equipped' ? 'route')
  from (select public.equip_cosmetic('route',null) w) x),'해제');

-- 칭호: 10km는 얻고, 하프는 반려된 기록이라 못 얻습니다. 새벽 러닝은 1회 진행입니다.
select public.my_titles() as titles \gset
select pg_temp.check_item((select (t->>'earned')::boolean from jsonb_array_elements(:'titles'::jsonb->'titles') t where t->>'code'='ten_k'),'10K 클럽 획득');
select pg_temp.check_item((select not (t->>'earned')::boolean and (t->>'progress')::int=10200
  from jsonb_array_elements(:'titles'::jsonb->'titles') t where t->>'code'='half'),'반려 기록 제외');
select pg_temp.check_item((select (t->>'progress')::int=1 and (t->>'goal')::int=10
  from jsonb_array_elements(:'titles'::jsonb->'titles') t where t->>'code'='dawn'),'새벽 러닝 진행');
select pg_temp.check_item(pg_temp.fails('select public.set_title(''half'')','P0001'),'못 얻은 칭호 선택 거부');
select pg_temp.check_item((public.set_title('ten_k')->>'selected')='ten_k','칭호 선택');

-- 다른 사람에게는 칭호·칭호 모양·말풍선이 보입니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000302',true);
select public.user_badges(array['00000000-0000-0000-0000-000000000301'::uuid]) as badges \gset
select pg_temp.check_item(:'badges'::jsonb->'00000000-0000-0000-0000-000000000301'->>'title'='ten_k'
  and :'badges'::jsonb->'00000000-0000-0000-0000-000000000301'->>'title_style'='title_crown'
  and :'badges'::jsonb->'00000000-0000-0000-0000-000000000301'->>'chat_bubble'='bubble_mint','다른 사람에게 보임');
select pg_temp.check_item(pg_temp.fails('select public.buy_cosmetic(''route_rainbow'')','P0001'),'코인 부족');
reset role;
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body)
 values('00000000-0000-0000-0000-000000000301',gen_random_uuid(),'national','free','칭호 글','내용');
select id as post from runspot_private.board_posts where title='칭호 글' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000302',true);
select pg_temp.check_item(public.post_author_badges(array[:'post'::uuid])->:'post'->>'title'='ten_k','게시글 글쓴이 칭호');
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values
 ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000302');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000302',true);
select pg_temp.check_item(public.user_badges(array['00000000-0000-0000-0000-000000000301'::uuid])='{}'::jsonb,'차단하면 안 보임');
reset role;
delete from runspot_private.blocks;

-- 크루 정원 확장권: 크루장만, 한 번만, 30명 → 50명
insert into runspot_private.crews(owner_id,name,icon) values('00000000-0000-0000-0000-000000000301','정원검증','star');
select id as crew from runspot_private.crews where name='정원검증' \gset
insert into runspot_private.crew_members(user_id,crew_id,role) values('00000000-0000-0000-0000-000000000301',:'crew','owner');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000302',true);
select pg_temp.check_item(pg_temp.fails(format('select public.expand_crew(%L)',:'crew'),'42501'),'크루장 아니면 거부');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
select pg_temp.check_item((select (crew->>'size_limit')::int=30 from jsonb_array_elements(public.my_crew()->'crews') crew
  where crew->>'name'='정원검증'),'기본 정원 30');
select pg_temp.check_item((select (w->>'coins')::int=3000-600-300-200-1000 from (select public.expand_crew(:'crew') w) x),'확장권 1000코인');
select pg_temp.check_item((select (crew->>'size_limit')::int=50 and (crew->>'expanded')::boolean
  from jsonb_array_elements(public.my_crew()->'crews') crew where crew->>'name'='정원검증'),'정원 50');
select pg_temp.check_item(pg_temp.fails(format('select public.expand_crew(%L)',:'crew'),'P0001'),'두 번 확장 거부');
reset role;
set local role anon;
select pg_temp.check_item(pg_temp.fails('select public.my_titles()','42501'),'익명 거부');
rollback;
