\set ON_ERROR_STOP on
begin;
create function pg_temp.check_rc(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000c71','rc71@example.com',now()),
  ('00000000-0000-0000-0000-000000000c72','rc72@example.com',now()),
  ('00000000-0000-0000-0000-000000000c73','rc73@example.com',now());
insert into runspot_private.owned_cosmetics(user_id,item,coins) values
  ('00000000-0000-0000-0000-000000000c72','char_cap_blue',150),
  ('00000000-0000-0000-0000-000000000c72','route_neon',150),
  ('00000000-0000-0000-0000-000000000c73','char_shoes_red',250);
insert into runspot_private.equipped_cosmetics(user_id,slot,item) values
  ('00000000-0000-0000-0000-000000000c72','char_head','char_cap_blue'),
  ('00000000-0000-0000-0000-000000000c72','route','route_neon'),
  ('00000000-0000-0000-0000-000000000c73','char_shoes','char_shoes_red');
-- c73은 c71을 차단했습니다.
insert into runspot_private.blocks(blocker_id,blocked_id) values
  ('00000000-0000-0000-0000-000000000c73','00000000-0000-0000-0000-000000000c71');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000c71',true);
select public.runner_characters(array[
  '00000000-0000-0000-0000-000000000c71','00000000-0000-0000-0000-000000000c72',
  '00000000-0000-0000-0000-000000000c73','00000000-0000-0000-0000-000000000c72']::uuid[]) as r \gset
select pg_temp.check_rc(:'r'::jsonb->'00000000-0000-0000-0000-000000000c72'='{"char_head":"char_cap_blue"}'::jsonb,'캐릭터 칸만 보임(경로 색 제외)');
select pg_temp.check_rc(:'r'::jsonb->'00000000-0000-0000-0000-000000000c71'='{}'::jsonb,'안 입은 나는 빈 객체');
select pg_temp.check_rc(not (:'r'::jsonb ? '00000000-0000-0000-0000-000000000c73'),'차단 관계는 빠짐');
select pg_temp.check_rc(pg_temp.fails($q$select public.runner_characters(array(select gen_random_uuid() from generate_series(1,101)))$q$,'22023'),'101명은 거절');
reset role;
set local role anon;
select pg_temp.check_rc(pg_temp.fails($q$select public.runner_characters(array['00000000-0000-0000-0000-000000000c72']::uuid[])$q$,'42501'),'로그인 안 하면 거절');
rollback;
