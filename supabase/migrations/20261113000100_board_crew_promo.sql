-- 게시판에 '크루 홍보'(board='crew')를 더하고, 러닝 소식 말머리에 '자유'(free)·'질문'(question)을 더합니다.
-- 크루 홍보글은 그 크루를 만든 크루장만 쓸 수 있고, 글에 크루 이름과 아이콘을 함께 보여줍니다.
alter table runspot_private.board_posts
  add column crew_id uuid references runspot_private.crews(id) on delete cascade;
create index board_posts_crew on runspot_private.board_posts(crew_id) where crew_id is not null;

-- 이름 없이 만든 게시판·말머리 제약을 찾아 새 규칙으로 바꿉니다.
do $$
declare item record;
begin
  for item in select conname from pg_constraint
    where conrelid='runspot_private.board_posts'::regclass and contype='c'
      and (pg_get_constraintdef(oid) like '%board%' or pg_get_constraintdef(oid) like '%topic%')
      and pg_get_constraintdef(oid) not like '%race_place%'
      and pg_get_constraintdef(oid) not like '%race_url%'
  loop
    execute format('alter table runspot_private.board_posts drop constraint %I',item.conname);
  end loop;
end;
$$;
alter table runspot_private.board_posts
  add constraint board_posts_board_kind check (board in ('local','national','race','crew')),
  add constraint board_posts_topic_kind check (topic in ('course','tip','food','free','question')),
  add constraint board_posts_local_region check ((board='local') = (region is not null)),
  add constraint board_posts_topic_needed check ((board in ('race','crew')) = (topic is null)),
  add constraint board_posts_race_fields check ((board='race') = (race_date is not null and race_place is not null)),
  add constraint board_posts_crew_needed check ((board='crew') = (crew_id is not null));

-- 내가 크루장인 크루 목록입니다. 크루 홍보글을 쓸 때 고릅니다.
create function runspot_private.board_own_crews(viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'icon',c.icon)
    order by c.created_at,c.id),'[]'::jsonb)
  from runspot_private.crews c where c.owner_id=viewer;
$$;
revoke all on function runspot_private.board_own_crews(uuid) from public,anon,authenticated;

create or replace function runspot_private.board_post_json(p runspot_private.board_posts,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p.id,'board',p.board,'topic',p.topic,'region',p.region,'title',p.title,'body',p.body,
    'nickname',coalesce((select nickname from public.profiles where id=p.author_id),'닉네임 없음'),
    'is_mine',p.author_id=viewer,'race_date',p.race_date,'race_place',p.race_place,'race_url',p.race_url,
    'created_at',p.created_at,'updated_at',p.updated_at,'images',to_jsonb(p.image_paths),
    'crew',(select jsonb_build_object('id',c.id,'name',c.name,'icon',c.icon)
      from runspot_private.crews c where c.id=p.crew_id),
    'like_count',(select count(*) from runspot_private.board_likes l where l.post_id=p.id
      and runspot_private.board_author_visible(l.user_id,viewer)),
    'liked',exists(select 1 from runspot_private.board_likes l where l.post_id=p.id and l.user_id=viewer),
    'comment_count',(select count(*) from runspot_private.board_comments c where c.post_id=p.id
      and runspot_private.board_author_visible(c.author_id,viewer)));
$$;

create or replace function runspot_private.check_board_fields(requested_board text,requested_topic text,title_value text,
  body_value text,requested_race_date date,place_value text,url_value text,images text[],owner_id uuid)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if requested_board is null or requested_board not in ('local','national','race','crew') then
    raise exception '게시판을 다시 선택해 주세요.' using errcode='22023';
  end if;
  if requested_board='race' then
    if requested_topic is not null or requested_race_date is null or place_value is null
      or char_length(place_value)>80 or (url_value is not null and (char_length(url_value)>500 or url_value !~ '^https://[^[:space:]]+$')) then
      raise exception '대회 날짜·장소와 https 링크를 확인해 주세요.' using errcode='22023';
    end if;
  elsif requested_board='crew' then
    if requested_topic is not null or requested_race_date is not null or place_value is not null or url_value is not null then
      raise exception '크루 홍보글에는 말머리를 붙이지 않습니다.' using errcode='22023';
    end if;
  elsif requested_topic is null or requested_topic not in ('course','tip','food','free','question')
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

-- 글쓰기에 크루를 고르는 requested_crew를 더합니다. 이전 앱은 이 값 없이 그대로 호출할 수 있습니다.
drop function public.create_board_post(uuid,text,text,text,text,date,text,text,text[]);
drop function runspot_private.create_board_post(uuid,text,text,text,text,date,text,text,text[]);
create function runspot_private.create_board_post(client_id uuid,requested_board text,requested_topic text,
  requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text,
  requested_images text[],requested_crew uuid)
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
  crew_value uuid;
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
  if requested_board='crew' then
    select c.id into crew_value from runspot_private.crews c where c.id=requested_crew and c.owner_id=viewer;
    if crew_value is null then
      raise exception '크루장만 크루 홍보글을 쓸 수 있습니다.' using errcode='42501';
    end if;
  elsif requested_crew is not null then
    raise exception '크루는 크루 홍보에서만 고를 수 있습니다.' using errcode='22023';
  end if;
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
  insert into runspot_private.board_posts(author_id,client_post_id,board,topic,region,title,body,race_date,race_place,race_url,
    image_paths,crew_id)
  values(viewer,client_id,requested_board,requested_topic,viewer_region,title_value,body_value,
    requested_race_date,place_value,url_value,images,crew_value)
  returning id into created;
  return created;
end;
$$;
revoke all on function runspot_private.create_board_post(uuid,text,text,text,text,date,text,text,text[],uuid)
  from public,anon,authenticated;
create function public.create_board_post(client_id uuid,requested_board text,requested_title text,requested_body text,
  requested_topic text default null,requested_race_date date default null,requested_race_place text default null,
  requested_race_url text default null,requested_images text[] default '{}',requested_crew uuid default null)
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.create_board_post(client_id,requested_board,requested_topic,requested_title,requested_body,
  requested_race_date,requested_race_place,requested_race_url,requested_images,requested_crew); $$;
revoke all on function public.create_board_post(uuid,text,text,text,text,date,text,text,text[],uuid) from public,anon;
grant execute on function public.create_board_post(uuid,text,text,text,text,date,text,text,text[],uuid) to authenticated;
grant execute on function runspot_private.create_board_post(uuid,text,text,text,text,date,text,text,text[],uuid) to authenticated;

create or replace function runspot_private.board_feed(requested_board text,requested_topic text,before_at timestamptz,before_id uuid,
  search_text text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  viewer_region text;
  staff boolean := runspot_private.staff_role() is not null;
  query_value text := nullif(btrim(search_text),'');
  pattern text;
  rows jsonb;
  has_more boolean := false;
  own_crews jsonb := runspot_private.board_own_crews(viewer);
begin
  if requested_board is null or requested_board not in ('news','local','national','race','crew')
    or (requested_topic is not null and (requested_board in ('race','crew')
      or requested_topic not in ('course','tip','food','free','question')))
    or ((before_at is null) <> (before_id is null)) then
    raise exception '게시판 조건을 확인해 주세요.' using errcode='22023';
  end if;
  if char_length(query_value) > 50 then
    raise exception '검색어는 50자 이내로 입력해 주세요.' using errcode='22023';
  end if;
  pattern := '%'||replace(replace(replace(query_value,'\','\\'),'%','\%'),'_','\_')||'%';
  select region into viewer_region from runspot_private.board_regions where user_id=viewer;
  if requested_board='race' then
    select coalesce(jsonb_agg(runspot_private.board_post_json(x.post,viewer)
      order by (x.post).race_date,(x.post).id),'[]'::jsonb) into rows
    from (select p as post from runspot_private.board_posts p where p.board='race'
      and p.race_date >= (now() at time zone 'Asia/Seoul')::date
      and (query_value is null or p.title ilike pattern or p.body ilike pattern)
      and runspot_private.board_author_visible(p.author_id,viewer)
      order by p.race_date,p.id limit 50) x;
  else
    select coalesce(jsonb_agg(runspot_private.board_post_json(x.post,viewer)
      order by (x.post).created_at desc,(x.post).id desc),'[]'::jsonb),
      count(*) > 20 into rows,has_more
    from (select p as post from runspot_private.board_posts p
      where (p.board=requested_board or (requested_board='news' and p.board in ('national','local')))
      and (p.board<>'local' or p.region=viewer_region)
      and (requested_topic is null or p.topic=requested_topic)
      and (query_value is null or p.title ilike pattern or p.body ilike pattern)
      and (before_at is null or (p.created_at,p.id) < (before_at,before_id))
      and runspot_private.board_author_visible(p.author_id,viewer)
      order by p.created_at desc,p.id desc limit 21) x;
    -- 다음 페이지 확인용으로 하나 더 읽은 글은 응답에서 제외합니다.
    if has_more then rows := rows - 20; end if;
  end if;
  return jsonb_build_object('region',viewer_region,'can_write',runspot_private.can_interact(),
    'can_post_race',staff,'can_moderate',staff,'own_crews',own_crews,'posts',rows,
    'next',case when has_more then jsonb_build_object('at',rows->-1->'created_at','id',rows->-1->'id') end);
end;
$$;
notify pgrst,'reload schema';
