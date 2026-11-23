-- 프로필 사진을 친구 목록·채팅·게시판 등 사람이 보이는 모든 곳에 보여줍니다.
-- 목록에서는 작은 사진(썸네일, 40KB 이하)만 받아 데이터 사용량을 줄입니다.
alter table runspot_private.profile_avatars
  add column thumb bytea check (thumb is null or octet_length(thumb) between 4 and 40960);

-- base64 JPEG를 확인하고 바이트로 바꿉니다. 형식이 틀리면 22023 오류입니다.
create function runspot_private.avatar_jpeg(value text,max_bytes integer)
returns bytea language plpgsql immutable set search_path='' as $$
declare image_bytes bytea;
begin
  if value is null or octet_length(value)>(max_bytes*4/3+8) then
    raise exception '사진 크기를 확인해 주세요.' using errcode='22023';
  end if;
  begin
    image_bytes := decode(value,'base64');
  exception when others then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end;
  -- JPEG 파일의 시작(FF D8)과 끝(FF D9)을 확인합니다.
  if octet_length(image_bytes) not between 4 and max_bytes
     or substring(image_bytes from 1 for 2)<>'\xffd8'::bytea
     or substring(image_bytes from octet_length(image_bytes)-1 for 2)<>'\xffd9'::bytea then
    raise exception '사진 형식을 확인해 주세요.' using errcode='22023';
  end if;
  return image_bytes;
end;
$$;
revoke all on function runspot_private.avatar_jpeg(text,integer) from public,anon,authenticated;

-- 큰 사진과 작은 사진을 함께 저장합니다. 작은 사진이 없으면(이전 앱) 큰 사진만 저장합니다.
drop function public.set_my_avatar(text);
drop function runspot_private.set_my_avatar(text);
create function runspot_private.set_my_avatar(jpeg text,thumb text default null)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid := auth.uid(); photo_bytes bytea; thumb_bytes bytea;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  photo_bytes := runspot_private.avatar_jpeg(jpeg,307200);
  if thumb is not null then thumb_bytes := runspot_private.avatar_jpeg(thumb,40960); end if;
  -- 짧은 시간에 반복해서 바꾸지 못하게 12초에 한 번만 바꿀 수 있습니다.
  if exists(select 1 from runspot_private.profile_avatars a
      where a.user_id=viewer and a.updated_at>clock_timestamp()-interval '12 seconds') then
    raise exception '잠시 후 다시 바꿔 주세요.' using errcode='P0001';
  end if;
  insert into runspot_private.profile_avatars(user_id,photo,thumb,updated_at)
  values(viewer,photo_bytes,thumb_bytes,clock_timestamp())
  on conflict(user_id) do update set photo=excluded.photo,thumb=excluded.thumb,updated_at=excluded.updated_at;
end;
$$;
create function public.set_my_avatar(jpeg text,thumb text default null) returns void language sql
security invoker set search_path='' as $$ select runspot_private.set_my_avatar(jpeg,thumb); $$;
revoke all on function runspot_private.set_my_avatar(text,text),public.set_my_avatar(text,text) from public,anon,authenticated;
grant execute on function runspot_private.set_my_avatar(text,text),public.set_my_avatar(text,text) to authenticated;

-- 화면에 나온 사람·글쓴이·댓글 작성자의 작은 사진을 한 번에 돌려줍니다.
-- 게시판은 글쓴이 ID를 앱에 주지 않으므로 글·댓글 ID로 찾습니다. 차단·비공개 등 볼 수 없는 사람은 빠집니다.
-- 결과: {"users":{id:{"photo":base64,"version":"..."}}, "posts":{...}, "comments":{...}}
create function runspot_private.profile_avatars(user_ids uuid[] default '{}',post_ids uuid[] default '{}',comment_ids uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if cardinality(coalesce(user_ids,'{}'))>100 or cardinality(coalesce(post_ids,'{}'))>100
     or cardinality(coalesce(comment_ids,'{}'))>100 then
    raise exception '사진은 한 번에 100개까지 조회할 수 있어요.' using errcode='22023';
  end if;
  return jsonb_build_object(
    'users',(select coalesce(jsonb_object_agg(a.user_id,jsonb_build_object(
        'photo',encode(coalesce(a.thumb,a.photo),'base64'),'version',a.updated_at)),'{}'::jsonb)
      from runspot_private.profile_avatars a
      where a.user_id=any(coalesce(user_ids,'{}'))
        and (a.user_id=viewer or runspot_private.board_author_visible(a.user_id,viewer))),
    'posts',(select coalesce(jsonb_object_agg(p.id,jsonb_build_object(
        'photo',encode(coalesce(a.thumb,a.photo),'base64'),'version',a.updated_at)),'{}'::jsonb)
      from runspot_private.board_posts p join runspot_private.profile_avatars a on a.user_id=p.author_id
      where p.id=any(coalesce(post_ids,'{}')) and runspot_private.board_post_visible(p.id,viewer)),
    'comments',(select coalesce(jsonb_object_agg(c.id,jsonb_build_object(
        'photo',encode(coalesce(a.thumb,a.photo),'base64'),'version',a.updated_at)),'{}'::jsonb)
      from runspot_private.board_comments c join runspot_private.profile_avatars a on a.user_id=c.author_id
      where c.id=any(coalesce(comment_ids,'{}')) and runspot_private.board_post_visible(c.post_id,viewer)
        and (c.author_id=viewer or runspot_private.board_author_visible(c.author_id,viewer))));
end;
$$;
create function public.profile_avatars(user_ids uuid[] default '{}',post_ids uuid[] default '{}',comment_ids uuid[] default '{}')
returns jsonb language sql stable security invoker set search_path=''
as $$ select runspot_private.profile_avatars(user_ids,post_ids,comment_ids); $$;
revoke all on function runspot_private.profile_avatars(uuid[],uuid[],uuid[]),public.profile_avatars(uuid[],uuid[],uuid[])
  from public,anon,authenticated;
grant execute on function runspot_private.profile_avatars(uuid[],uuid[],uuid[]),public.profile_avatars(uuid[],uuid[],uuid[])
  to authenticated;
notify pgrst,'reload schema';
