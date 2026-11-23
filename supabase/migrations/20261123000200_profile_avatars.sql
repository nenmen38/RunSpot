-- 프로필 사진: 내 갤러리에서 고른 사진을 정사각형 JPEG(300KB 이하)로 저장합니다.
-- 본인만 바꾸고 지울 수 있으며, 다른 사람은 차단 관계가 아닐 때만 볼 수 있습니다.
create table runspot_private.profile_avatars (
  user_id uuid primary key references auth.users(id) on delete cascade,
  photo bytea not null check (octet_length(photo) between 4 and 307200),
  updated_at timestamptz not null default now()
);
alter table runspot_private.profile_avatars enable row level security;
revoke all on runspot_private.profile_avatars from public,anon,authenticated;

create function runspot_private.set_my_avatar(jpeg text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := auth.uid(); image_bytes bytea;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  if jpeg is null or octet_length(jpeg)>409600 then
    raise exception '사진은 300KB 이하로 올려 주세요.' using errcode='22023';
  end if;
  begin
    image_bytes := decode(jpeg,'base64');
  exception when others then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end;
  -- JPEG 파일의 시작(FF D8)과 끝(FF D9)을 확인합니다.
  if octet_length(image_bytes) not between 4 and 307200
     or substring(image_bytes from 1 for 2)<>'\xffd8'::bytea
     or substring(image_bytes from octet_length(image_bytes)-1 for 2)<>'\xffd9'::bytea then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end if;
  -- 짧은 시간에 반복해서 바꾸지 못하게 12초에 한 번만 바꿀 수 있습니다.
  if exists(select 1 from runspot_private.profile_avatars a
      where a.user_id=viewer and a.updated_at>clock_timestamp()-interval '12 seconds') then
    raise exception '잠시 후 다시 바꿔 주세요.' using errcode='P0001';
  end if;
  insert into runspot_private.profile_avatars(user_id,photo,updated_at) values(viewer,image_bytes,clock_timestamp())
  on conflict(user_id) do update set photo=excluded.photo,updated_at=excluded.updated_at;
end;
$$;

create function runspot_private.remove_my_avatar()
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  delete from runspot_private.profile_avatars where user_id=auth.uid();
end;
$$;

-- 사진(base64)을 돌려줍니다. 없거나 볼 수 없으면 null입니다.
create function runspot_private.user_avatar(target uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := auth.uid();
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  if target<>viewer and (not runspot_private.is_active(target) or exists(select 1 from runspot_private.blocks b
      where (b.blocker_id=viewer and b.blocked_id=target) or (b.blocker_id=target and b.blocked_id=viewer))) then
    return null;
  end if;
  return (select encode(a.photo,'base64') from runspot_private.profile_avatars a where a.user_id=target);
end;
$$;

create function public.set_my_avatar(jpeg text) returns void language sql security invoker set search_path=''
as $$ select runspot_private.set_my_avatar(jpeg); $$;
create function public.remove_my_avatar() returns void language sql security invoker set search_path=''
as $$ select runspot_private.remove_my_avatar(); $$;
create function public.user_avatar(target uuid) returns text language sql stable security invoker set search_path=''
as $$ select runspot_private.user_avatar(target); $$;
revoke all on function runspot_private.set_my_avatar(text),runspot_private.remove_my_avatar(),runspot_private.user_avatar(uuid),
  public.set_my_avatar(text),public.remove_my_avatar(),public.user_avatar(uuid) from public,anon,authenticated;
grant execute on function runspot_private.set_my_avatar(text),runspot_private.remove_my_avatar(),runspot_private.user_avatar(uuid),
  public.set_my_avatar(text),public.remove_my_avatar(),public.user_avatar(uuid) to authenticated;
notify pgrst,'reload schema';
