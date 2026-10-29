-- 게시판 대댓글과 키워드 검색입니다. 답글이 달리면 원댓글 작성자에게도 알림을 남깁니다.
alter table runspot_private.board_comments
  add column parent_id uuid references runspot_private.board_comments(id) on delete cascade;
create index board_comments_parent on runspot_private.board_comments(parent_id) where parent_id is not null;

alter table runspot_private.notifications
  drop constraint notifications_kind_check,
  drop constraint notifications_check,
  add constraint notifications_kind_check check (kind in ('like','comment','reply')),
  add constraint notifications_check check ((kind in ('comment','reply')) = (comment_id is not null));

-- 글 작성자에게는 댓글 알림을, 원댓글 작성자에게는 답글 알림을 남깁니다. 같은 사람이면 댓글 알림 하나만 남깁니다.
create or replace function runspot_private.notify_board_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into runspot_private.notifications(recipient_id,actor_id,kind,post_id,comment_id)
  select p.author_id,new.author_id,'comment',new.post_id,new.id from runspot_private.board_posts p
  where p.id=new.post_id and p.author_id<>new.author_id;
  if new.parent_id is not null then
    insert into runspot_private.notifications(recipient_id,actor_id,kind,post_id,comment_id)
    select c.author_id,new.author_id,'reply',new.post_id,new.id
    from runspot_private.board_comments c join runspot_private.board_posts p on p.id=c.post_id
    where c.id=new.parent_id and c.author_id<>new.author_id and c.author_id<>p.author_id;
  end if;
  return null;
end;
$$;

-- 답글은 원댓글이 보일 때만 보여줍니다. 앱이 원댓글 아래에 묶어 표시합니다.
create or replace function runspot_private.board_comments(post_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  perform runspot_private.require_visible_board_post(post_id,viewer);
  return jsonb_build_object('can_write',runspot_private.can_interact(),
    'can_moderate',runspot_private.staff_role() is not null,
    'comments',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'parent_id',c.parent_id,'body',c.body,
      'nickname',coalesce(pr.nickname,'닉네임 없음'),'is_mine',c.author_id=viewer,'created_at',c.created_at)
      order by c.created_at,c.id),'[]'::jsonb)
    from (select * from runspot_private.board_comments c where c.post_id=board_comments.post_id
      and runspot_private.board_author_visible(c.author_id,viewer)
      and (c.parent_id is null or exists(select 1 from runspot_private.board_comments pc
        where pc.id=c.parent_id and runspot_private.board_author_visible(pc.author_id,viewer)))
      order by c.created_at,c.id limit 300) c
    left join public.profiles pr on pr.id=c.author_id));
end;
$$;

-- 답글은 한 단계만 허용합니다. 답글에 다시 답하면 앱이 원댓글을 부모로 보냅니다.
drop function public.create_board_comment(uuid,uuid,text);
drop function runspot_private.create_board_comment(uuid,uuid,text);
create function runspot_private.create_board_comment(client_id uuid,post_id uuid,requested_body text,parent_comment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  body_value text := btrim(requested_body);
  parent runspot_private.board_comments;
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
  if parent_comment_id is not null then
    select * into parent from runspot_private.board_comments c where c.id=parent_comment_id for share;
    if not found or parent.post_id<>create_board_comment.post_id
      or not runspot_private.board_author_visible(parent.author_id,viewer) then
      raise exception '삭제되었거나 볼 수 없는 댓글입니다.' using errcode='P0001';
    end if;
    if parent.parent_id is not null then
      raise exception '답글에는 다시 답글을 달 수 없습니다.' using errcode='22023';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('board_comments:'||viewer::text,0));
  select id into existing from runspot_private.board_comments where author_id=viewer and client_comment_id=client_id;
  if found then return existing; end if;
  if exists(select 1 from runspot_private.board_comments where author_id=viewer and created_at > now()-interval '5 seconds') then
    raise exception '잠시 후 다시 작성해 주세요.' using errcode='P0001';
  end if;
  if (select count(*) from runspot_private.board_comments where author_id=viewer and created_at > now()-interval '1 day') >= 100 then
    raise exception '하루에 작성할 수 있는 댓글은 100개입니다.' using errcode='P0001';
  end if;
  insert into runspot_private.board_comments(post_id,author_id,client_comment_id,body,parent_id)
  values(post_id,viewer,client_id,body_value,parent_comment_id) returning id into created;
  return created;
end;
$$;
create function public.create_board_comment(client_id uuid,post_id uuid,requested_body text,parent_comment_id uuid default null)
returns uuid language sql security invoker set search_path = ''
as $$ select runspot_private.create_board_comment(client_id,post_id,requested_body,parent_comment_id); $$;

-- 제목·내용에 검색어가 들어간 글만 고릅니다. %, _ 는 글자 그대로 찾습니다.
drop function public.board_feed(text,text,timestamptz,uuid);
drop function runspot_private.board_feed(text,text,timestamptz,uuid);
create function runspot_private.board_feed(requested_board text,requested_topic text,before_at timestamptz,before_id uuid,
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
begin
  if requested_board is null or requested_board not in ('local','national','race')
    or (requested_topic is not null and (requested_board='race' or requested_topic not in ('course','tip','food')))
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
    from (select p as post from runspot_private.board_posts p where p.board=requested_board
      and (requested_board<>'local' or p.region=viewer_region)
      and (requested_topic is null or p.topic=requested_topic)
      and (query_value is null or p.title ilike pattern or p.body ilike pattern)
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
create function public.board_feed(requested_board text,requested_topic text default null,
  before_at timestamptz default null,before_id uuid default null,search_text text default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.board_feed(requested_board,requested_topic,before_at,before_id,search_text); $$;

revoke all on function
  runspot_private.create_board_comment(uuid,uuid,text,uuid),public.create_board_comment(uuid,uuid,text,uuid),
  runspot_private.board_feed(text,text,timestamptz,uuid,text),public.board_feed(text,text,timestamptz,uuid,text)
  from public,anon,authenticated;
grant execute on function
  runspot_private.create_board_comment(uuid,uuid,text,uuid),public.create_board_comment(uuid,uuid,text,uuid),
  runspot_private.board_feed(text,text,timestamptz,uuid,text),public.board_feed(text,text,timestamptz,uuid,text)
  to authenticated;
notify pgrst,'reload schema';
