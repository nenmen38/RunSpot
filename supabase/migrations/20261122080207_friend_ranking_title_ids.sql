-- 친구 랭킹에 칭호 조회에 필요한 사용자 ID를 추가합니다.
create or replace function runspot_private.runner_ranking(category text,audience text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid(); week_start timestamptz := date_trunc('week',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'; result jsonb;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  if category is null or category not in ('distance','consistency','longest','five_k') or audience is null or audience not in ('friends','all') then
    raise exception '랭킹 기준을 확인해 주세요.' using errcode='22023';
  end if;
  if not runspot_private.can_interact() then
    return jsonb_build_object('can_interact',false,'week_started_at',week_start,'entries','[]'::jsonb);
  end if;
  with participants as materialized (
    select p.id,p.nickname from public.profiles p
    where p.id=viewer or (
      p.nickname is not null and runspot_private.email_verified(p.id)
      and runspot_private.can_read(p.id,p.visibility)
      and ((audience='all' and p.visibility='public') or (audience='friends' and exists(
        select 1 from public.friendships f where f.user_low=least(viewer,p.id) and f.user_high=greatest(viewer,p.id) and f.status='accepted')))
    )
  ), eligible as materialized (
    select r.* from public.runs r join participants p on p.id=r.user_id
    where r.ended_at<=now() and r.distance_m>=300 and r.duration_sec>0
      and not r.review_pending and r.integrity_status<>'rejected'
      and (category='five_k' or r.ended_at>=week_start)
      and (category<>'five_k' or r.distance_m>=5000)
  ), splits as (
    select r.user_id,r.id,s.ordinality,
      (s.value->>'distance_m')::numeric as metres,(s.value->>'duration_us')::bigint as micros
    from eligible r cross join lateral jsonb_array_elements(r.split_data) with ordinality s
    where category='five_k'
  ), windows as (
    select user_id,count(*) over w as n,min(metres) over w as metres,min(micros) over w as positive,sum(micros) over w as elapsed
    from splits window w as (partition by id order by ordinality rows between current row and 4 following)
  ), scores as (
    select user_id,case when category='distance' then floor(sum(distance_m))::bigint
      when category='longest' then floor(max(distance_m))::bigint
      else count(distinct (ended_at at time zone 'Asia/Seoul')::date) end as score
      from eligible where category<>'five_k' group by user_id
    union all
    select user_id,min(elapsed)::bigint from windows where n=5 and metres=1000 and positive>0 group by user_id
  ), ranked as (
    select case when s.score>0 then rank() over(order by case when category='five_k' then -s.score else s.score end desc nulls last) else 0 end as rank,
      p.id,p.nickname,coalesce(s.score,0) as score,p.id=viewer as is_me
    from participants p left join scores s on p.id=s.user_id
    where audience='friends' or s.score>0 or p.id=viewer
  )
  select coalesce(jsonb_agg(jsonb_build_object('rank',rank,'nickname',nickname,'score',score,'is_me',is_me)
    || case when audience='friends' then jsonb_build_object('user_id',id) else '{}'::jsonb end
    order by (rank=0),rank,nickname,id),'[]'::jsonb) into result from ranked where (rank>0 and rank<=100) or is_me or (audience='friends' and rank=0);
  return jsonb_build_object('can_interact',true,'week_started_at',week_start,'entries',result);
end;
$$;

create or replace function runspot_private.friend_weekly_ranking()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if not runspot_private.can_interact() then
    return jsonb_build_object('can_interact', false, 'week_started_at', week_start, 'entries', '[]'::jsonb);
  end if;
  return (
    with participants as (
      select p.id, p.nickname from public.profiles p where p.id=viewer
      union all
      select p.id, p.nickname from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      where viewer in (f.user_low,f.user_high) and f.status='accepted'
        and p.nickname is not null and runspot_private.email_verified(p.id)
        and runspot_private.can_read(p.id,p.visibility)
    ), totals as (
      select p.id, p.nickname, coalesce(sum(r.distance_m),0) as distance_m
      from participants p left join public.runs r on r.user_id=p.id
        and r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
        and r.ended_at <= now() and not r.review_pending and r.integrity_status <> 'rejected'
      group by p.id,p.nickname
    ), ranked as (
      select rank() over(order by t.distance_m desc) as rank,
        t.id, t.nickname, t.distance_m, t.id=viewer as is_me from totals t
    )
    select jsonb_build_object('can_interact',true,'week_started_at',week_start,
      'entries',coalesce(jsonb_agg(jsonb_build_object(
        'rank',r.rank,'nickname',r.nickname,'distance_m',r.distance_m,'is_me',r.is_me,'user_id',r.id
      ) order by r.distance_m desc,r.nickname,r.id),'[]'::jsonb)) from ranked r
  );
end;
$$;
