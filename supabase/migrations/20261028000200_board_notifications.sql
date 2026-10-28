-- 내 게시글에 좋아요·댓글이 달리면 알림을 남깁니다. 원본은 비노출 스키마에 두고 RPC로만 접근합니다.
create table runspot_private.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('like','comment')),
  post_id uuid not null references runspot_private.board_posts(id) on delete cascade,
  comment_id uuid references runspot_private.board_comments(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check ((kind='comment') = (comment_id is not null))
);
-- 좋아요를 취소했다가 다시 눌러도 같은 사람의 좋아요 알림은 하나만 남깁니다.
create unique index notifications_like_once on runspot_private.notifications(post_id,actor_id) where kind='like';
create index notifications_recipient on runspot_private.notifications(recipient_id,created_at desc,id desc);
create index notifications_actor on runspot_private.notifications(actor_id);
create index notifications_comment on runspot_private.notifications(comment_id) where comment_id is not null;
alter table runspot_private.notifications enable row level security;
revoke all on runspot_private.notifications from public,anon,authenticated;

create function runspot_private.notify_board_like()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into runspot_private.notifications(recipient_id,actor_id,kind,post_id)
  select p.author_id,new.user_id,'like',new.post_id from runspot_private.board_posts p
  where p.id=new.post_id and p.author_id<>new.user_id
  on conflict (post_id,actor_id) where kind='like' do nothing;
  return null;
end;
$$;
create function runspot_private.notify_board_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into runspot_private.notifications(recipient_id,actor_id,kind,post_id,comment_id)
  select p.author_id,new.author_id,'comment',new.post_id,new.id from runspot_private.board_posts p
  where p.id=new.post_id and p.author_id<>new.author_id;
  return null;
end;
$$;
revoke all on function runspot_private.notify_board_like(),runspot_private.notify_board_comment()
  from public,anon,authenticated;
create trigger board_likes_notify after insert on runspot_private.board_likes
  for each row execute function runspot_private.notify_board_like();
create trigger board_comments_notify after insert on runspot_private.board_comments
  for each row execute function runspot_private.notify_board_comment();

-- 지금 보여줄 수 있는 알림만 고릅니다. 좋아요를 취소했거나 차단·정지된 사용자, 볼 수 없게 된 글의 알림은 숨깁니다.
create function runspot_private.notification_visible(n runspot_private.notifications,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.board_author_visible(n.actor_id,viewer)
    and runspot_private.board_post_visible(n.post_id,viewer)
    and (n.kind<>'like' or exists(select 1 from runspot_private.board_likes l
      where l.post_id=n.post_id and l.user_id=n.actor_id));
$$;
revoke all on function runspot_private.notification_visible(runspot_private.notifications,uuid)
  from public,anon,authenticated;

-- 확성기 표시용으로 읽지 않은 알림 수를 100개까지만 셉니다.
create function runspot_private.unread_notification_count()
returns integer language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select count(*) from (select 1 from runspot_private.notifications n
    where n.recipient_id=viewer and n.read_at is null and runspot_private.notification_visible(n,viewer)
    limit 100) x);
end;
$$;

-- 최근 알림 50개를 최신순으로 반환합니다.
create function runspot_private.my_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'post_id',x.post_id,
      'post_title',p.title,'nickname',coalesce(pr.nickname,'닉네임 없음'),
      'comment',left(c.body,80),'created_at',x.created_at,'read',x.read_at is not null)
      order by x.created_at desc,x.id desc),'[]'::jsonb)
    from (select * from runspot_private.notifications n where n.recipient_id=viewer
      and runspot_private.notification_visible(n,viewer) order by n.created_at desc,n.id desc limit 50) x
    join runspot_private.board_posts p on p.id=x.post_id
    left join runspot_private.board_comments c on c.id=x.comment_id
    left join public.profiles pr on pr.id=x.actor_id);
end;
$$;

-- 화면에 보여준 시각까지의 알림만 읽음으로 바꿔, 그 사이 새로 온 알림은 그대로 남깁니다.
create function runspot_private.mark_notifications_read(seen_until timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  if seen_until is null then raise exception '알림 시각을 확인해 주세요.' using errcode='22023'; end if;
  update runspot_private.notifications set read_at=now()
  where recipient_id=viewer and read_at is null and created_at<=seen_until;
  -- 오래된 알림은 읽음 처리할 때 함께 정리합니다.
  delete from runspot_private.notifications where recipient_id=viewer and created_at < now()-interval '90 days';
end;
$$;

-- 알림에서 글을 바로 열 수 있도록 글 하나를 게시판 목록과 같은 형식으로 반환합니다.
create function runspot_private.board_post(post_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  staff boolean := runspot_private.staff_role() is not null;
begin
  perform runspot_private.require_visible_board_post(post_id,viewer);
  return jsonb_build_object('region',(select region from runspot_private.board_regions where user_id=viewer),
    'can_write',runspot_private.can_interact(),'can_post_race',staff,'can_moderate',staff,
    'posts',(select jsonb_build_array(runspot_private.board_post_json(p,viewer))
      from runspot_private.board_posts p where p.id=board_post.post_id),
    'next',null);
end;
$$;

create function public.unread_notification_count() returns integer language sql stable security invoker set search_path = ''
as $$ select runspot_private.unread_notification_count(); $$;
create function public.my_notifications() returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_notifications(); $$;
create function public.mark_notifications_read(seen_until timestamptz) returns void language sql security invoker set search_path = ''
as $$ select runspot_private.mark_notifications_read(seen_until); $$;
create function public.board_post(post_id uuid) returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.board_post(post_id); $$;

revoke all on function
  runspot_private.unread_notification_count(),runspot_private.my_notifications(),
  runspot_private.mark_notifications_read(timestamptz),runspot_private.board_post(uuid),
  public.unread_notification_count(),public.my_notifications(),
  public.mark_notifications_read(timestamptz),public.board_post(uuid)
  from public,anon,authenticated;
grant execute on function
  runspot_private.unread_notification_count(),runspot_private.my_notifications(),
  runspot_private.mark_notifications_read(timestamptz),runspot_private.board_post(uuid),
  public.unread_notification_count(),public.my_notifications(),
  public.mark_notifications_read(timestamptz),public.board_post(uuid)
  to authenticated;
notify pgrst,'reload schema';
