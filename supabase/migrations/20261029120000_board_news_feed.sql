-- 앱의 '러닝 소식'은 전국 글과 내 동네 글을 함께 최신순으로 보여줍니다. 동네 글만 보려면 'local'을 씁니다.
-- 글은 계속 'national'·'local'로 저장하므로 저장 형식과 이전 앱은 바뀌지 않습니다.
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
begin
  if requested_board is null or requested_board not in ('news','local','national','race')
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
    'can_post_race',staff,'can_moderate',staff,'posts',rows,
    'next',case when has_more then jsonb_build_object('at',rows->-1->'created_at','id',rows->-1->'id') end);
end;
$$;
notify pgrst,'reload schema';
