-- 게시판 원본은 비노출 스키마에 두고 화면에는 RPC 결과만 제공합니다.
create table runspot_private.board_regions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  region text not null check (region ~ '^[가-힣]{2,10}( [가-힣]{1,10})?$'),
  updated_at timestamptz not null default now()
);
create table runspot_private.board_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  client_post_id uuid not null,
  board text not null check (board in ('local','national','race')),
  topic text check (topic in ('course','tip','food')),
  -- 동네 글은 작성 당시 동네에 고정하며 이후 작성자가 동네를 바꿔도 옮기지 않습니다.
  region text check (region ~ '^[가-힣]{2,10}( [가-힣]{1,10})?$'),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 2000),
  race_date date,
  race_place text check (char_length(race_place) between 1 and 80),
  race_url text check (char_length(race_url) <= 500 and race_url ~ '^https://[^[:space:]]+$'),
  created_at timestamptz not null default now(),
  unique(author_id,client_post_id),
  check ((board='local') = (region is not null)),
  check ((board='race') = (topic is null)),
  check ((board='race') = (race_date is not null and race_place is not null)),
  check (board='race' or race_url is null)
);
create index board_posts_local on runspot_private.board_posts(region,created_at desc,id desc) where board='local';
create index board_posts_national on runspot_private.board_posts(created_at desc,id desc) where board='national';
create index board_posts_race on runspot_private.board_posts(race_date,id) where board='race';
create index board_posts_author on runspot_private.board_posts(author_id,created_at desc);
alter table runspot_private.board_regions enable row level security;
alter table runspot_private.board_posts enable row level security;
revoke all on runspot_private.board_regions,runspot_private.board_posts from public,anon,authenticated;

create function runspot_private.require_board_viewer()
returns uuid language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return auth.uid();
end;
$$;
revoke all on function runspot_private.require_board_viewer() from public,anon,authenticated;

create function runspot_private.my_board_region()
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  return (select region from runspot_private.board_regions where user_id=runspot_private.require_board_viewer());
end;
$$;

create function runspot_private.set_my_board_region(requested_region text)
returns text language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); value text := btrim(requested_region);
begin
  if value is null or value !~ '^[가-힣]{2,10}( [가-힣]{1,10})?$' then
    raise exception '동네를 목록에서 다시 선택해 주세요.' using errcode='22023';
  end if;
  insert into runspot_private.board_regions(user_id,region) values(viewer,value)
  on conflict(user_id) do update set region=excluded.region,updated_at=now();
  return value;
end;
$$;

create function runspot_private.board_author_visible(author uuid,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.is_active(author) and not exists(select 1 from runspot_private.blocks b where
    (b.blocker_id=viewer and b.blocked_id=author) or (b.blocker_id=author and b.blocked_id=viewer));
$$;
create function runspot_private.board_post_json(p runspot_private.board_posts,viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p.id,'board',p.board,'topic',p.topic,'region',p.region,'title',p.title,'body',p.body,
    'nickname',coalesce((select nickname from public.profiles where id=p.author_id),'닉네임 없음'),
    'is_mine',p.author_id=viewer,'race_date',p.race_date,'race_place',p.race_place,'race_url',p.race_url,
    'created_at',p.created_at);
$$;
revoke all on function runspot_private.board_author_visible(uuid,uuid),
  runspot_private.board_post_json(runspot_private.board_posts,uuid) from public,anon,authenticated;

-- 동네·전국 글은 최신순 20개씩, 대회 공지는 오늘 이후 일정만 날짜순으로 반환합니다.
create function runspot_private.board_feed(requested_board text,requested_topic text,before_at timestamptz,before_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  viewer_region text;
  staff boolean := runspot_private.staff_role() is not null;
  rows jsonb;
  has_more boolean := false;
begin
  if requested_board is null or requested_board not in ('local','national','race')
    or (requested_topic is not null and (requested_board='race' or requested_topic not in ('course','tip','food')))
    or ((before_at is null) <> (before_id is null)) then
    raise exception '게시판 조건을 확인해 주세요.' using errcode='22023';
  end if;
  select region into viewer_region from runspot_private.board_regions where user_id=viewer;
  if requested_board='race' then
    select coalesce(jsonb_agg(runspot_private.board_post_json(x.post,viewer)
      order by (x.post).race_date,(x.post).id),'[]'::jsonb) into rows
    from (select p as post from runspot_private.board_posts p where p.board='race'
      and p.race_date >= (now() at time zone 'Asia/Seoul')::date
      and runspot_private.board_author_visible(p.author_id,viewer)
      order by p.race_date,p.id limit 50) x;
  else
    select coalesce(jsonb_agg(runspot_private.board_post_json(x.post,viewer)
      order by (x.post).created_at desc,(x.post).id desc),'[]'::jsonb),
      count(*) > 20 into rows,has_more
    from (select p as post from runspot_private.board_posts p where p.board=requested_board
      and (requested_board<>'local' or p.region=viewer_region)
      and (requested_topic is null or p.topic=requested_topic)
      and (before_at is null or (p.created_at,p.id) < (before_at,before_id))
      and runspot_private.board_author_visible(p.author_id,viewer)
      order by p.created_at desc,p.id desc limit 21) x;
    -- 다음 페이지 확인용으로 하나 더 읽은 글은 응답에서 제외합니다.
    if has_more then rows := rows - 20; end if;
  end if;
  return jsonb_build_object('region',viewer_region,'can_write',runspot_private.can_interact(),
    'can_post_race',staff,'can_moderate',staff,'posts',rows,
    'next',case when has_more then jsonb_build_object('at',rows->-1->'created_at','id',rows->-1->'id') end);
end;
$$;

create function runspot_private.create_board_post(client_id uuid,requested_board text,requested_topic text,
  requested_title text,requested_body text,requested_race_date date,requested_race_place text,requested_race_url text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  viewer_region text;
  existing uuid;
  title_value text := btrim(requested_title);
  body_value text := btrim(requested_body);
  place_value text := nullif(btrim(requested_race_place),'');
  url_value text := nullif(btrim(requested_race_url),'');
  created uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '이메일 인증과 닉네임 등록 후 글을 쓸 수 있습니다.' using errcode='42501';
  end if;
  if requested_board='race' and runspot_private.staff_role() is null then
    raise exception '러닝 대회 공지는 관리자만 등록할 수 있습니다.' using errcode='42501';
  end if;
  if client_id is null or requested_board is null or requested_board not in ('local','national','race') then
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
  insert into runspot_private.board_posts(author_id,client_post_id,board,topic,region,title,body,race_date,race_place,race_url)
  values(viewer,client_id,requested_board,requested_topic,viewer_region,title_value,body_value,
    requested_race_date,place_value,url_value)
  returning id into created;
  return created;
end;
$$;

create function runspot_private.delete_board_post(post_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer(); owner_id uuid;
begin
  select author_id into owner_id from runspot_private.board_posts where id=post_id for update;
  -- 이미 삭제된 글의 재요청은 무해하게 처리합니다.
  if not found then return; end if;
  if owner_id<>viewer then
    perform 1 from runspot_private.user_roles where user_id=viewer for share;
    if runspot_private.staff_role() is null then
      raise exception '본인 글만 삭제할 수 있습니다.' using errcode='42501';
    end if;
    insert into runspot_private.audit_logs(actor_id,action,target_id) values(viewer,'board_post_delete',post_id);
  end if;
  delete from runspot_private.board_posts where id=post_id;
end;
$$;

create function public.my_board_region() returns text language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_board_region(); $$;
create function public.set_my_board_region(requested_region text) returns text language sql security invoker set search_path = ''
as $$ select runspot_private.set_my_board_region(requested_region); $$;
create function public.board_feed(requested_board text,requested_topic text default null,
  before_at timestamptz default null,before_id uuid default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.board_feed(requested_board,requested_topic,before_at,before_id); $$;
create function public.create_board_post(client_id uuid,requested_board text,requested_title text,requested_body text,
  requested_topic text default null,requested_race_date date default null,requested_race_place text default null,
  requested_race_url text default null)
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.create_board_post(client_id,requested_board,requested_topic,requested_title,requested_body,
  requested_race_date,requested_race_place,requested_race_url); $$;
create function public.delete_board_post(post_id uuid) returns void language sql security invoker set search_path = ''
as $$ select runspot_private.delete_board_post(post_id); $$;

revoke all on function runspot_private.my_board_region(),runspot_private.set_my_board_region(text),
  runspot_private.board_feed(text,text,timestamptz,uuid),
  runspot_private.create_board_post(uuid,text,text,text,text,date,text,text),
  runspot_private.delete_board_post(uuid),
  public.my_board_region(),public.set_my_board_region(text),public.board_feed(text,text,timestamptz,uuid),
  public.create_board_post(uuid,text,text,text,text,date,text,text),public.delete_board_post(uuid)
  from public,anon,authenticated;
grant execute on function runspot_private.my_board_region(),
  runspot_private.set_my_board_region(text),runspot_private.board_feed(text,text,timestamptz,uuid),
  runspot_private.create_board_post(uuid,text,text,text,text,date,text,text),
  runspot_private.delete_board_post(uuid),
  public.my_board_region(),public.set_my_board_region(text),public.board_feed(text,text,timestamptz,uuid),
  public.create_board_post(uuid,text,text,text,text,date,text,text),public.delete_board_post(uuid)
  to authenticated;
notify pgrst,'reload schema';
