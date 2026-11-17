create table runspot_private.friend_invite_links(
 user_id uuid primary key references auth.users(id) on delete cascade,
 token uuid not null unique default gen_random_uuid(),expires_at timestamptz not null default now()+interval '7 days'
);
alter table runspot_private.friend_invite_links enable row level security;
revoke all on runspot_private.friend_invite_links from public,anon,authenticated;
create function runspot_private.friend_invite(operation text default 'mine',token uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); target uuid; result jsonb;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 if operation in ('mine','renew') then
   perform pg_advisory_xact_lock(hashtextextended('friend_invite:'||viewer::text,0));
   insert into runspot_private.friend_invite_links(user_id) values(viewer) on conflict do nothing;
   if operation='renew' then update runspot_private.friend_invite_links set token=gen_random_uuid(),expires_at=now()+interval '7 days' where user_id=viewer; end if;
   select jsonb_build_object('token',l.token,'expires_at',l.expires_at) into result from runspot_private.friend_invite_links l where user_id=viewer;
   return result;
 elsif operation in ('preview','request') then
   select l.user_id into target from runspot_private.friend_invite_links l where l.token=friend_invite.token and l.expires_at>now();
   if target is null or target=viewer or not runspot_private.is_active(target) or exists(select 1 from runspot_private.blocks where (blocker_id=viewer and blocked_id=target) or (blocker_id=target and blocked_id=viewer)) then raise exception '만료되었거나 사용할 수 없는 초대입니다.' using errcode='42501'; end if;
   if operation='request' then perform runspot_private.change_friend(target,'request',null); end if;
   return (select jsonb_build_object('nickname',nickname) from public.profiles where id=target);
 else raise exception '지원하지 않는 초대 작업입니다.' using errcode='22023'; end if;
end;
$$;
create function public.friend_invite(operation text default 'mine',token uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.friend_invite(operation,token); $$;
revoke all on function public.friend_invite(text,uuid),runspot_private.friend_invite(text,uuid) from public,anon,authenticated;
grant execute on function public.friend_invite(text,uuid),runspot_private.friend_invite(text,uuid) to authenticated;
notify pgrst,'reload schema';
