\set ON_ERROR_STOP on
begin;
create function pg_temp.check_cheer(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000b71','cheer71@example.com',now()),
 ('00000000-0000-0000-0000-000000000b72','cheer72@example.com',now()),
 ('00000000-0000-0000-0000-000000000b73','cheer73@example.com',now());
update public.profiles set nickname=case id when '00000000-0000-0000-0000-000000000b71' then '보내는러너' else '받는러너' end
 where id in ('00000000-0000-0000-0000-000000000b71','00000000-0000-0000-0000-000000000b72');
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000b71','00000000-0000-0000-0000-000000000b72','00000000-0000-0000-0000-000000000b71','accepted');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000b71',true);
select pg_temp.check_cheer(pg_temp.fails($q$select public.send_cheer('00000000-0000-0000-0000-000000000b72')$q$,'P0001'),'달리지 않는 친구는 안 됨');
select pg_temp.check_cheer(pg_temp.fails($q$select public.send_cheer('00000000-0000-0000-0000-000000000b73')$q$,'42501'),'친구가 아니면 안 됨');
reset role;
insert into runspot_private.live_locations(user_id,latitude,longitude,updated_at)
 values('00000000-0000-0000-0000-000000000b72',37.5,127,now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000b71',true);
select public.send_cheer('00000000-0000-0000-0000-000000000b72');
select pg_temp.check_cheer(pg_temp.fails($q$select public.send_cheer('00000000-0000-0000-0000-000000000b72')$q$,'P0001'),'1분에 한 번');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000b72',true);
select public.take_my_cheers() as c \gset
select pg_temp.check_cheer(jsonb_array_length(:'c'::jsonb)=1 and :'c'::jsonb->0->>'nickname'='보내는러너','응원 받기');
select pg_temp.check_cheer(jsonb_array_length(public.take_my_cheers())=0,'한 번만 들음');
reset role;
-- 차단하면 받지 않습니다.
insert into runspot_private.run_cheers(sender_id,recipient_id) values
 ('00000000-0000-0000-0000-000000000b71','00000000-0000-0000-0000-000000000b72');
insert into runspot_private.blocks(blocker_id,blocked_id) values
 ('00000000-0000-0000-0000-000000000b72','00000000-0000-0000-0000-000000000b71');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000b72',true);
select pg_temp.check_cheer(jsonb_array_length(public.take_my_cheers())=0,'차단한 사람 응원 제외');
rollback;
