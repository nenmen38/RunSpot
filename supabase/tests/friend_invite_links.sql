\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(ok boolean,message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',message;end if;end;$$;
create function pg_temp.fails(statement text,code text) returns boolean language plpgsql as $$begin execute statement;return false;exception when others then return sqlstate=code;end;$$;
\set sender '00000000-0000-0000-0000-000000000421'
\set reader '00000000-0000-0000-0000-000000000422'
insert into auth.users(id,email,email_confirmed_at) values(:'sender','invite421@example.com',now()),(:'reader','invite422@example.com',now());
update public.profiles set nickname='초대검증'||right(id::text,3) where id in (:'sender',:'reader');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'sender',true);
select public.friend_invite()->>'token' as token \gset
select set_config('request.jwt.claim.sub',:'reader',true);
select pg_temp.ok(public.friend_invite('preview',:'token')->>'nickname'='초대검증421','초대 대상 확인');
select public.friend_invite('request',:'token');
reset role;
select pg_temp.ok((select status='pending' from public.friendships where requested_by=:'reader'),'초대만으로 친구 자동 수락 금지');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'sender',true);
select public.friend_invite('renew');
select set_config('request.jwt.claim.sub',:'reader',true);
select pg_temp.ok(pg_temp.fails(format('select public.friend_invite(''preview'',%L)',:'token'),'42501'),'폐기 링크 무효화');
rollback;
