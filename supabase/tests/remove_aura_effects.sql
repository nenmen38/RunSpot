\set ON_ERROR_STOP on
begin;
create function pg_temp.check_aura(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000341','aura341@example.com',now());
update public.profiles set nickname='오라검증341' where id='00000000-0000-0000-0000-000000000341';
insert into runspot_private.coin_grants(user_id,coins,reason) values('00000000-0000-0000-0000-000000000341',1000,'테스트');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000341',true);
select pg_temp.check_aura(pg_temp.fails('select public.buy_cosmetic(''aura_flame'')','22023'),'오라 효과는 팔지 않음');
select pg_temp.check_aura((select (w->>'coins')::int=600 from (select public.buy_cosmetic('route_neon') w) x),'다른 아이템은 그대로');
rollback;
