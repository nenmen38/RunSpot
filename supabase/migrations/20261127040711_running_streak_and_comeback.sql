-- 연속 기록(스트릭)과 '러닝 응원' 알림입니다.
-- 1) my_running_streak(): 주간 목표(없으면 주 1회 이상 달리기)를 몇 주 연속 지켰는지 알려 줍니다.
-- 2) 매일 저녁 7시(한국 시간)에 마지막 러닝 뒤 3·7·14일째인 사람에게 '러너가 기다리고 있어요' 알림을 보냅니다.
--    설정에서 '러닝 응원'을 끄면 보내지 않습니다. 알림 서버 함수(operations-worker)를 다시 배포해야 합니다.

create function runspot_private.my_running_streak()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  goal_m integer;
  this_week date := date_trunc('week', now() at time zone 'Asia/Seoul')::date;
  result jsonb;
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode = '42501';
  end if;
  select kilometers * 1000 into goal_m from runspot_private.weekly_goals
    where user_id = viewer and kilometers is not null;
  with weeks as (
    select w, coalesce(sum(r.distance_m), 0) as meters, count(r.id) as runs
    from generate_series(0, 52) w
    left join public.runs r on r.user_id = viewer and r.integrity_status <> 'rejected' and not r.hidden
      and (r.started_at at time zone 'Asia/Seoul')::date >= this_week - w * 7
      and (r.started_at at time zone 'Asia/Seoul')::date < this_week - (w - 1) * 7
    group by w
  ), ok as (
    select w, meters, case when goal_m is null then runs > 0 else meters >= goal_m end as achieved from weeks
  )
  select jsonb_build_object(
    'goal_based', goal_m is not null,
    'this_week_done', (select achieved from ok where w = 0),
    'this_week_m', (select meters from ok where w = 0),
    'goal_m', goal_m,
    -- 지난주부터 거꾸로 이어진 주 수에, 이번 주를 이미 지켰으면 1을 더합니다.
    'weeks', coalesce((select min(w) from ok where w >= 1 and not achieved), 53) - 1
      + case when (select achieved from ok where w = 0) then 1 else 0 end,
    'days_since_last_run', (select (now() at time zone 'Asia/Seoul')::date - max((r.ended_at at time zone 'Asia/Seoul')::date)
      from public.runs r where r.user_id = viewer and r.integrity_status <> 'rejected')
  ) into result;
  return result;
end;
$$;
create function public.my_running_streak()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_running_streak(); $$;
revoke all on function runspot_private.my_running_streak(), public.my_running_streak() from public, anon, authenticated;
grant execute on function runspot_private.my_running_streak(), public.my_running_streak() to authenticated;

-- 응원 알림 설정(기본 켬)과 알림 종류를 더합니다.
alter table runspot_private.push_preferences add column comeback boolean not null default true;
alter table runspot_private.push_jobs drop constraint push_jobs_kind_check;
alter table runspot_private.push_jobs add constraint push_jobs_kind_check
  check(kind in ('friend_request','group_invite','board_comment','friend_message','room_message','board_like','crew_invite','comeback'));

create or replace function runspot_private.push_allowed(j runspot_private.push_jobs)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.is_active(j.recipient_id) and runspot_private.is_active(j.actor_id)
 and not exists(select 1 from runspot_private.blocks where (blocker_id=j.actor_id and blocked_id=j.recipient_id) or (blocker_id=j.recipient_id and blocked_id=j.actor_id))
 and coalesce((select case j.kind when 'friend_request' then p.friend_request when 'group_invite' then p.group_invite
   when 'friend_message' then p.friend_message when 'room_message' then p.room_message
   when 'board_like' then p.board_like when 'crew_invite' then p.crew_invite when 'comeback' then p.comeback else p.board_comment end
  from runspot_private.push_preferences p where p.user_id=j.recipient_id),true)
 and case j.kind
 when 'friend_request' then exists(select 1 from public.friendships f where f.relationship_id=j.target_id and f.status='pending' and f.requested_by=j.actor_id)
 when 'group_invite' then exists(select 1 from runspot_private.running_groups g join runspot_private.running_group_members m on m.group_id=g.id
  where g.id=j.target_id and g.state='lobby' and g.expires_at>now() and m.user_id=j.recipient_id and m.status='invited')
 when 'friend_message' then exists(select 1 from public.friendships f
   where f.user_low=least(j.recipient_id,j.actor_id) and f.user_high=greatest(j.recipient_id,j.actor_id) and f.status='accepted')
  and exists(select 1 from runspot_private.friend_messages m where m.kind<>'deleted' and 'chat:'||m.id=j.source_key
   and m.id>runspot_private.friend_chat_last_read(j.recipient_id,j.actor_id))
 when 'room_message' then runspot_private.is_chat_room_member(j.target_id,j.recipient_id)
  and exists(select 1 from runspot_private.chat_room_messages m where m.room_id=j.target_id
   and j.source_key='room:'||m.id||':'||j.recipient_id
   and m.id>runspot_private.chat_room_last_read(j.target_id,j.recipient_id))
 when 'board_like' then exists(select 1 from runspot_private.notifications n where 'like:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id))
 -- 응원 알림: 알림을 만든 뒤에도 여전히 3일 넘게 달리지 않았을 때만 보냅니다.
 when 'comeback' then not exists(select 1 from public.runs r where r.user_id=j.recipient_id
   and r.ended_at>j.created_at-interval '3 days')
 when 'crew_invite' then exists(select 1 from runspot_private.notifications n
   join runspot_private.crew_invites i on i.crew_id=n.crew_id and i.user_id=j.recipient_id and i.status='invited'
   where 'crew:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id))
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;

create or replace function runspot_private.push_text(j runspot_private.push_jobs)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 who text := coalesce((select nullif(p.nickname,'') from public.profiles p where p.id=j.actor_id),'러너');
 preview boolean := coalesce((select p.show_preview from runspot_private.push_preferences p where p.user_id=j.recipient_id),true);
 content text;
 room text;
 note text;
begin
 -- 응원 알림은 이름·내용이 없으므로 미리보기 설정과 관계없이 같은 문구입니다.
 if j.kind='comeback' then
  return jsonb_build_object('title','뜀터','body',case
   when j.source_key like '%:3' then '러너가 운동화를 신고 기다리고 있어요 👟 오늘 가볍게 10분만 달려 볼까요?'
   when j.source_key like '%:7' then '일주일째 쉬는 중이에요. 러너가 몸이 근질근질하대요 🏃'
   else '오랜만이에요! 러너가 트랙에서 기다리고 있어요. 다시 시작해 볼까요?' end);
 end if;
 if not preview then
  return jsonb_build_object('title','뜀터','body',case j.kind
   when 'friend_request' then '새 친구 요청이 도착했어요.'
   when 'group_invite' then '함께 달리기 초대가 도착했어요.'
   when 'crew_invite' then '크루 초대가 도착했어요.'
   when 'board_like' then '내 글에 좋아요가 달렸어요.'
   when 'friend_message' then '새 메시지가 도착했어요.'
   when 'room_message' then '단체 대화방에 새 메시지가 도착했어요.'
   else '내 글이나 댓글에 새 댓글이 달렸어요.' end);
 end if;
 case j.kind
 when 'friend_message' then
  select case m.kind when 'photo' then '사진을 보냈어요.' when 'run' then '러닝 기록을 공유했어요.' else m.body end
   into content from runspot_private.friend_messages m where 'chat:'||m.id=j.source_key;
  return jsonb_build_object('title',who,'body',left(coalesce(content,'새 메시지가 도착했어요.'),120));
 when 'room_message' then
  select case m.kind when 'photo' then '사진을 보냈어요.' else m.body end
   into content from runspot_private.chat_room_messages m where m.room_id=j.target_id and j.source_key='room:'||m.id||':'||j.recipient_id;
  room := runspot_private.chat_room_title(j.target_id,j.recipient_id);
  return jsonb_build_object('title',left(room,40),'body',left(who||': '||coalesce(content,'새 메시지'),120));
 when 'board_comment' then
  select c.body,n.kind into content,note from runspot_private.notifications n
   join runspot_private.board_comments c on c.id=n.comment_id where 'comment:'||n.id=j.source_key;
  return jsonb_build_object('title',case note when 'reply' then '새 답글' else '새 댓글' end,
   'body',left(who||': '||coalesce(content,''),120));
 when 'board_like' then
  select b.title into content from runspot_private.board_posts b where b.id=j.target_id;
  return jsonb_build_object('title','좋아요','body',left(who||'님이 내 글을 좋아해요: '||coalesce(content,''),120));
 when 'crew_invite' then
  select c.name into content from runspot_private.crews c where c.id=j.target_id;
  return jsonb_build_object('title','크루 초대','body',left(who||'님이 '||coalesce(content,'크루')||' 크루에 초대했어요.',120));
 when 'group_invite' then
  return jsonb_build_object('title','함께 달리기 초대','body',who||'님이 함께 달리기에 초대했어요.');
 else
  return jsonb_build_object('title','친구 요청','body',who||'님이 친구 요청을 보냈어요.');
 end case;
end;
$$;

-- 매일 한 번: 마지막 러닝이 정확히 3·7·14일 전인 사람에게 응원 알림 작업을 만듭니다(같은 날 두 번 만들지 않음).
create function runspot_private.enqueue_comeback_pushes()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  made integer;
begin
  insert into runspot_private.push_jobs(recipient_id, actor_id, kind, target_id, source_key)
  select last_runs.user_id, last_runs.user_id, 'comeback', last_runs.user_id,
    'comeback:' || last_runs.user_id || ':' || today || ':' || (today - last_runs.last_day)
  from (
    select r.user_id, max((r.ended_at at time zone 'Asia/Seoul')::date) as last_day
    from public.runs r
    where r.integrity_status <> 'rejected' and r.ended_at > now() - interval '16 days'
    group by r.user_id
  ) last_runs
  where today - last_runs.last_day in (3, 7, 14)
    and runspot_private.is_active(last_runs.user_id)
    and exists(select 1 from runspot_private.push_devices d where d.user_id = last_runs.user_id)
  on conflict(source_key) do nothing;
  get diagnostics made = row_count;
  return made;
end;
$$;
revoke all on function runspot_private.enqueue_comeback_pushes() from public, anon, authenticated;
select cron.schedule('runspot-comeback-pushes', '0 10 * * *', 'select runspot_private.enqueue_comeback_pushes();');

drop function public.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean);
drop function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean);
create function runspot_private.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null,room_message boolean default null,
  board_like boolean default null,crew_invite boolean default null,show_preview boolean default null,comeback boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); result jsonb;
begin
 if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 insert into runspot_private.push_preferences as p(user_id) values(viewer) on conflict(user_id) do nothing;
 update runspot_private.push_preferences p set
  friend_request=coalesce(my_push_preferences.friend_request,p.friend_request),
  group_invite=coalesce(my_push_preferences.group_invite,p.group_invite),
  board_comment=coalesce(my_push_preferences.board_comment,p.board_comment),
  friend_message=coalesce(my_push_preferences.friend_message,p.friend_message),
  room_message=coalesce(my_push_preferences.room_message,p.room_message),
  board_like=coalesce(my_push_preferences.board_like,p.board_like),
  crew_invite=coalesce(my_push_preferences.crew_invite,p.crew_invite),
  show_preview=coalesce(my_push_preferences.show_preview,p.show_preview),
  comeback=coalesce(my_push_preferences.comeback,p.comeback)
 where p.user_id=viewer
 returning to_jsonb(p)-'user_id' into result;
 return result;
end;
$$;
create function public.my_push_preferences(friend_request boolean default null,group_invite boolean default null,
  board_comment boolean default null,friend_message boolean default null,room_message boolean default null,
  board_like boolean default null,crew_invite boolean default null,show_preview boolean default null,comeback boolean default null)
returns jsonb language sql security invoker set search_path='' as $$
  select runspot_private.my_push_preferences(friend_request,group_invite,board_comment,friend_message,
   room_message,board_like,crew_invite,show_preview,comeback);
$$;
revoke all on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function runspot_private.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean),
  public.my_push_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean) to authenticated;
notify pgrst, 'reload schema';
