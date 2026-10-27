-- 게시판 좋아요·댓글·사진 첨부와 글 수정 시 사진 변경입니다. 원본은 비노출 스키마에 두고 RPC로만 접근합니다.
alter table runspot_private.board_posts
  add column image_paths text[] not null default '{}' check (cardinality(image_paths) <= 4);
create index board_posts_images on runspot_private.board_posts using gin(image_paths);

create table runspot_private.board_likes (
  post_id uuid not null references runspot_private.board_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create index board_likes_user on runspot_private.board_likes(user_id);
create table runspot_private.board_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references runspot_private.board_posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  client_comment_id uuid not null,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now(),
  unique(author_id,client_comment_id)
);
create index board_comments_post on runspot_private.board_comments(post_id,created_at,id);
create index board_comments_author on runspot_private.board_comments(author_id,created_at desc);
alter table runspot_private.board_likes enable row level security;
alter table runspot_private.board_comments enable row level security;
revoke all on runspot_private.board_likes,runspot_private.board_comments from public,anon,authenticated;

-- 목록에 보이는 글만 좋아요·댓글·사진 조회를 허용합니다. 동네 글은 같은 동네 주민과 작성자만 봅니다.
create function runspot_private.board_post_visible(target uuid,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.board_posts p where p.id=target
    and runspot_private.board_author_visible(p.author_id,viewer)
    and (p.board<>'local' or p.author_id=viewer
      or p.region=(select region from runspot_private.board_regions where user_id=viewer)));
$$;
revoke all on function runspot_private.board_post_visible(uuid,uuid) from public,anon,authenticated;

create function runspot_private.require_visible_board_post(target uuid,viewer uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if target is null or not runspot_private.board_post_visible(target,viewer) then
    raise exception '삭제되었거나 볼 수 없는 글입니다.' using errcode='P0001';
  end if;
end;
$$;
revoke all on function runspot_private.require_visible_board_post(uuid,uuid) from public,anon,authenticated;

-- 사진은 작성자 폴더의 `작성자ID/무작위ID.jpg`만 허용합니다. 앱이 메타데이터를 제거한 JPEG로 다시 저장합니다.
create function runspot_private.valid_board_images(paths text[],owner_id uuid)
returns boolean language sql immutable set search_path = '' as $$
  select paths is not null and cardinality(paths) <= 4 and array_position(paths,null) is null
    and (select count(distinct x)=cardinality(paths) from unnest(paths) x)
    and not exists(select 1 from unnest(paths) x where x !~
      ('^'||owner_id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'));
$$;
revoke all on function runspot_private.valid_board_images(text[],uuid) from public,anon,authenticated;

create or replace function runspot_private.board_post_json(p runspot_private.board_posts,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p.id,'board',p.board,'topic',p.topic,'region',p.region,'title',p.title,'body',p.body,
    'nickname',coalesce((select nickname from public.profiles where id=p.author_id),'닉네임 없음'),
    'is_mine',p.author_id=viewer,'race_date',p.race_date,'race_place',p.race_place,'race_url',p.race_url,
    'created_at',p.created_at,'updated_at',p.updated_at,'images',to_jsonb(p.image_paths),
    'like_count',(select count(*) from runspot_private.board_likes l where l.post_id=p.id
      and runspot_private.board_author_visible(l.user_id,viewer)),
    'liked',exists(select 1 from runspot_private.board_likes l where l.post_id=p.id and l.user_id=viewer),
    'comment_count',(select count(*) from runspot_private.board_comments c where c.post_id=p.id
      and runspot_private.board_author_visible(c.author_id,viewer)));
$$;

-- 작성과 수정이 같은 규칙을 쓰도록 입력 검사를 한곳에 둡니다.
create function runspot_private.check_board_fields(requested_board text,requested_topic text,title_value text,
  body_value text,requested_race_date date,place_value text,url_value text,images text[],owner_id uuid)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if requested_board is null or requested_board not in ('local','national','race') then
    raise exception '게시판을 다시 선택해 주세요.' using errcode='22023';
  end if;
  if requested_board='race' then
    if requested_topic is not null or requested_race_date is null or place_value is null
      or char_length(place_value)>80 or (url_value is not null and (char_length(url_value)>500 or url_value !~ '^https://[^[:space:]]+$')) then
      raise exception '대회 날짜·장소와 https 링크를 확인해 주세요.' using errcode='22023';
    end if;
  elsif requested_topic is null or requested_topic not in ('course','tip','food')
    or requested_race_date is not null or place_value is not null or url_value is not null then
    raise exception '말머리를 선택해 주세요.' using errcode='22023';
  end if;
  if title_value is null or char_length(title_value) not between 1 and 80
    or body_value is null or char_length(body_value) not between 1 and 2000 then
    raise exception '제목은 1~80자, 내용은 1~2000자로 입력해 주세요.' using errcode='22023';
  end if;
  if not runspot_private.valid_board_images(images,owner_id) then
    raise exception '사진은 4장까지 다시 첨부해 주세요.' using errcode='22023';
  end if;
end;
$$;
revoke all on function runspot_private.check_board_fields(text,text,text,text,date,text,text,text[],uuid) from public,anon,authenticated;

drop function public.create_board_post(uuid,text,text,text,text,date,text,text);
drop function runspot_private.create_board_post(uuid,text,text,text,text,date,text,text);
create function runspot_private.create_board_post(client_id uuid,requested_board text,requested_topic text,
  requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text,
  requested_images text[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  viewer_region text;
  existing uuid;
  title_value text := btrim(requested_title);
  body_value text := btrim(requested_body);
  place_value text := nullif(btrim(requested_race_place),'');
  url_value text := nullif(btrim(requested_race_url),'');
  images text[] := coalesce(requested_images,'{}');
  created uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 글을 쓸 수 있습니다.' using errcode='42501';
  end if;
  if requested_board='race' and runspot_private.staff_role() is null then
    raise exception '러닝 대회 공지는 관리자만 등록할 수 있습니다.' using errcode='42501';
  end if;
  if client_id is null then
    raise exception '게시판을 다시 선택해 주세요.' using errcode='22023';
  end if;
  perform runspot_private.check_board_fields(requested_board,requested_topic,title_value,body_value,
    requested_race_date,place_value,url_value,images,viewer);
  -- 같은 작성자의 동시 요청을 직렬화해 재전송 중복과 작성 한도 우회를 막습니다.
  perform pg_advisory_xact_lock(hashtextextended('board_posts:'||viewer::text,0));
  select id into existing from runspot_private.board_posts where author_id=viewer and client_post_id=client_id;
  if found then return existing; end if;
  if requested_board='local' then
    select region into viewer_region from runspot_private.board_regions where user_id=viewer;
    if viewer_region is null then
      raise exception '동네를 먼저 설정해 주세요.' using errcode='22023';
    end if;
  end if;
  if exists(select 1 from runspot_private.board_posts where author_id=viewer and created_at > now()-interval '30 seconds') then
    raise exception '잠시 후 다시 작성해 주세요.' using errcode='P0001';
  end if;
  if (select count(*) from runspot_private.board_posts where author_id=viewer and created_at > now()-interval '1 day') >= 20 then
    raise exception '하루에 작성할 수 있는 글은 20개입니다.' using errcode='P0001';
  end if;
  insert into runspot_private.board_posts(author_id,client_post_id,board,topic,region,title,body,race_date,race_place,race_url,image_paths)
  values(viewer,client_id,requested_board,requested_topic,viewer_region,title_value,body_value,
    requested_race_date,place_value,url_value,images)
  returning id into created;
  return created;
end;
$$;

-- 기존 글 수정(update_my_board_post)에 사진 변경을 더합니다. requested_images가 null이면 사진은 그대로 둡니다.
-- 같은 내용 재전송은 무해하게 처리하고 다른 수정이 끼어들었으면 덮어쓰지 않는 기존 규칙을 유지합니다.
drop function public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text);
drop function runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text);
create function runspot_private.update_my_board_post(post_id uuid,expected_updated_at timestamptz,requested_topic text,
  requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text,
  requested_images text[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  item runspot_private.board_posts;
  title_value text := btrim(requested_title);
  body_value text := btrim(requested_body);
  place_value text := nullif(btrim(requested_race_place),'');
  url_value text := nullif(btrim(requested_race_url),'');
  images text[];
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록을 확인해 주세요.' using errcode='42501';
  end if;
  select * into item from runspot_private.board_posts where id=post_id for update;
  if not found or item.author_id<>viewer then
    raise exception '본인 글만 수정할 수 있습니다.' using errcode='42501';
  end if;
  if item.board='race' and runspot_private.staff_role() is null then
    raise exception '대회 공지 수정에는 관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  images := coalesce(requested_images,item.image_paths);
  perform runspot_private.check_board_fields(item.board,requested_topic,title_value,body_value,
    requested_race_date,place_value,url_value,images,viewer);
  if item.title=title_value and item.body=body_value and item.topic is not distinct from requested_topic
    and item.race_date is not distinct from requested_race_date and item.race_place is not distinct from place_value
    and item.race_url is not distinct from url_value and item.image_paths=images then return; end if;
  if expected_updated_at is null or item.updated_at<>expected_updated_at then
    raise exception '글이 변경되었습니다. 새로고침 후 다시 수정해 주세요.' using errcode='P0001';
  end if;
  update runspot_private.board_posts set title=title_value,body=body_value,topic=requested_topic,race_date=requested_race_date,
    race_place=place_value,race_url=url_value,image_paths=images,updated_at=clock_timestamp() where id=post_id;
end;
$$;

create function runspot_private.set_board_like(post_id uuid,liked boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 좋아요를 누를 수 있습니다.' using errcode='42501';
  end if;
  if liked is null then raise exception '좋아요 상태를 확인해 주세요.' using errcode='22023'; end if;
  perform runspot_private.require_visible_board_post(post_id,viewer);
  -- 같은 요청을 반복해도 결과가 같도록 추가·삭제를 멱등으로 처리합니다.
  if liked then
    insert into runspot_private.board_likes(post_id,user_id) values(post_id,viewer) on conflict do nothing;
  else
    delete from runspot_private.board_likes l where l.post_id=set_board_like.post_id and l.user_id=viewer;
  end if;
  return jsonb_build_object('liked',liked,'like_count',(select count(*) from runspot_private.board_likes l
    where l.post_id=set_board_like.post_id and runspot_private.board_author_visible(l.user_id,viewer)));
end;
$$;

create function runspot_private.board_comments(post_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  perform runspot_private.require_visible_board_post(post_id,viewer);
  return jsonb_build_object('can_write',runspot_private.can_interact(),
    'can_moderate',runspot_private.staff_role() is not null,
    'comments',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,
      'nickname',coalesce(pr.nickname,'닉네임 없음'),'is_mine',c.author_id=viewer,'created_at',c.created_at)
      order by c.created_at,c.id),'[]'::jsonb)
    from (select * from runspot_private.board_comments c where c.post_id=board_comments.post_id
      and runspot_private.board_author_visible(c.author_id,viewer) order by c.created_at,c.id limit 200) c
    left join public.profiles pr on pr.id=c.author_id));
end;
$$;

create function runspot_private.create_board_comment(client_id uuid,post_id uuid,requested_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  body_value text := btrim(requested_body);
  existing uuid;
  created uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 댓글을 쓸 수 있습니다.' using errcode='42501';
  end if;
  if client_id is null or body_value is null or char_length(body_value) not between 1 and 500 then
    raise exception '댓글은 1~500자로 입력해 주세요.' using errcode='22023';
  end if;
  perform runspot_private.require_visible_board_post(post_id,viewer);
  perform pg_advisory_xact_lock(hashtextextended('board_comments:'||viewer::text,0));
  select id into existing from runspot_private.board_comments where author_id=viewer and client_comment_id=client_id;
  if found then return existing; end if;
  if exists(select 1 from runspot_private.board_comments where author_id=viewer and created_at > now()-interval '5 seconds') then
    raise exception '잠시 후 다시 작성해 주세요.' using errcode='P0001';
  end if;
  if (select count(*) from runspot_private.board_comments where author_id=viewer and created_at > now()-interval '1 day') >= 100 then
    raise exception '하루에 작성할 수 있는 댓글은 100개입니다.' using errcode='P0001';
  end if;
  insert into runspot_private.board_comments(post_id,author_id,client_comment_id,body)
  values(post_id,viewer,client_id,body_value) returning id into created;
  return created;
end;
$$;

create function runspot_private.delete_board_comment(comment_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); owner_id uuid;
begin
  select author_id into owner_id from runspot_private.board_comments where id=comment_id for update;
  if not found then return; end if;
  if owner_id<>viewer then
    perform 1 from runspot_private.user_roles where user_id=viewer for share;
    if runspot_private.staff_role() is null then
      raise exception '본인 댓글만 삭제할 수 있습니다.' using errcode='42501';
    end if;
    insert into runspot_private.audit_logs(actor_id,action,target_id) values(viewer,'board_comment_delete',comment_id);
  end if;
  delete from runspot_private.board_comments where id=comment_id;
end;
$$;

-- 사진 파일은 작성자 본인 폴더에만 올리고, 자기 사진이나 볼 수 있는 글의 사진만 내려받습니다.
create function runspot_private.can_read_board_image(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and runspot_private.is_active(auth.uid()) and (
    split_part(object_name,'/',1)=auth.uid()::text
    or exists(select 1 from runspot_private.board_posts p where p.image_paths @> array[object_name]
      and runspot_private.board_post_visible(p.id,auth.uid())));
$$;
create function runspot_private.can_upload_board_image(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.can_interact() and runspot_private.valid_board_images(array[object_name],auth.uid());
$$;
revoke all on function runspot_private.can_read_board_image(text),runspot_private.can_upload_board_image(text)
  from public,anon,authenticated;
grant execute on function runspot_private.can_read_board_image(text),runspot_private.can_upload_board_image(text)
  to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('board-images','board-images',false,3145728,array['image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy board_images_read on storage.objects for select to authenticated
using (bucket_id='board-images' and runspot_private.can_read_board_image(name));
create policy board_images_insert on storage.objects for insert to authenticated
with check (bucket_id='board-images' and runspot_private.can_upload_board_image(name));
create policy board_images_delete on storage.objects for delete to authenticated
using (bucket_id='board-images' and split_part(name,'/',1)=auth.uid()::text);

create function public.create_board_post(client_id uuid,requested_board text,requested_title text,requested_body text,
  requested_topic text default null,requested_race_date date default null,requested_race_place text default null,
  requested_race_url text default null,requested_images text[] default '{}')
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.create_board_post(client_id,requested_board,requested_topic,requested_title,requested_body,
  requested_race_date,requested_race_place,requested_race_url,requested_images); $$;
create function public.update_my_board_post(post_id uuid,expected_updated_at timestamptz,requested_topic text,
  requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text,
  requested_images text[] default null)
returns void language sql security invoker set search_path = ''
as $$ select runspot_private.update_my_board_post(post_id,expected_updated_at,requested_topic,requested_title,requested_body,
  requested_race_date,requested_race_place,requested_race_url,requested_images); $$;
create function public.set_board_like(post_id uuid,liked boolean) returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.set_board_like(post_id,liked); $$;
create function public.board_comments(post_id uuid) returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.board_comments(post_id); $$;
create function public.create_board_comment(client_id uuid,post_id uuid,requested_body text)
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.create_board_comment(client_id,post_id,requested_body); $$;
create function public.delete_board_comment(comment_id uuid) returns void language sql security invoker set search_path = ''
as $$ select runspot_private.delete_board_comment(comment_id); $$;

revoke all on function
  runspot_private.create_board_post(uuid,text,text,text,text,date,text,text,text[]),
  runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text,text[]),
  runspot_private.set_board_like(uuid,boolean),runspot_private.board_comments(uuid),
  runspot_private.create_board_comment(uuid,uuid,text),runspot_private.delete_board_comment(uuid),
  public.create_board_post(uuid,text,text,text,text,date,text,text,text[]),
  public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text,text[]),
  public.set_board_like(uuid,boolean),public.board_comments(uuid),
  public.create_board_comment(uuid,uuid,text),public.delete_board_comment(uuid)
  from public,anon,authenticated;
grant execute on function
  runspot_private.create_board_post(uuid,text,text,text,text,date,text,text,text[]),
  runspot_private.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text,text[]),
  runspot_private.set_board_like(uuid,boolean),runspot_private.board_comments(uuid),
  runspot_private.create_board_comment(uuid,uuid,text),runspot_private.delete_board_comment(uuid),
  public.create_board_post(uuid,text,text,text,text,date,text,text,text[]),
  public.update_my_board_post(uuid,timestamptz,text,text,text,date,text,text,text[]),
  public.set_board_like(uuid,boolean),public.board_comments(uuid),
  public.create_board_comment(uuid,uuid,text),public.delete_board_comment(uuid)
  to authenticated;
notify pgrst,'reload schema';
