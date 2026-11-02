-- 함께 달리기 초대를 확성기 알림으로 보내고, 알림창에서 바로 수락·거절할 수 있게 합니다.
-- 수락·거절은 기존 group_action(accept/reject)을 그대로 쓰므로 친구·인증·차단 확인 규칙이 같습니다.
alter table runspot_private.notifications
  alter column post_id drop not null,
  add column group_id uuid references runspot_private.running_groups(id) on delete cascade,
  drop constraint notifications_kind_check,
  add constraint notifications_kind_check check (kind in ('like','comment','reply','group_invite')),
  add constraint notifications_target_check check (case when kind='group_invite'
    then group_id is not null and post_id is null else post_id is not null and group_id is null end);
create unique index notifications_group_invite_once on runspot_private.notifications(group_id,recipient_id)
  where kind='group_invite';
create index notifications_group on runspot_private.notifications(group_id) where group_id is not null;

create function runspot_private.notify_group_invite()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into runspot_private.notifications(recipient_id,actor_id,kind,group_id)
  select new.user_id,g.host_id,'group_invite',g.id from runspot_private.running_groups g
  where g.id=new.group_id and g.host_id<>new.user_id
  on conflict (group_id,recipient_id) where kind='group_invite' do nothing;
  return null;
end;
$$;
revoke all on function runspot_private.notify_group_invite() from public,anon,authenticated;
create trigger running_group_members_notify after insert on runspot_private.running_group_members
  for each row when (new.status='invited') execute function runspot_private.notify_group_invite();

-- 초대 알림은 차단·정지되지 않은 방장의 초대이고 아직 그 그룹의 초대 기록이 있을 때만 보여줍니다.
create or replace function runspot_private.notification_visible(n runspot_private.notifications,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.board_author_visible(n.actor_id,viewer) and case when n.kind='group_invite'
    then exists(select 1 from runspot_private.running_group_members m where m.group_id=n.group_id and m.user_id=viewer)
    else runspot_private.board_post_visible(n.post_id,viewer)
      and (n.kind<>'like' or exists(select 1 from runspot_private.board_likes l
        where l.post_id=n.post_id and l.user_id=n.actor_id)) end;
$$;

-- 초대 알림에는 내 응답 상태와 지금 응답할 수 있는지를 함께 보냅니다.
create or replace function runspot_private.my_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'post_id',x.post_id,
      'post_title',p.title,'nickname',coalesce(pr.nickname,'닉네임 없음'),
      'comment',left(c.body,80),'created_at',x.created_at,'read',x.read_at is not null,
      'group_id',x.group_id,'invite_status',m.status,
      'can_respond',x.kind='group_invite' and m.status='invited' and g.state='lobby' and g.expires_at>now())
      order by x.created_at desc,x.id desc),'[]'::jsonb)
    from (select * from runspot_private.notifications n where n.recipient_id=viewer
      and runspot_private.notification_visible(n,viewer) order by n.created_at desc,n.id desc limit 50) x
    left join runspot_private.board_posts p on p.id=x.post_id
    left join runspot_private.board_comments c on c.id=x.comment_id
    left join runspot_private.running_groups g on g.id=x.group_id
    left join runspot_private.running_group_members m on m.group_id=x.group_id and m.user_id=viewer
    left join public.profiles pr on pr.id=x.actor_id);
end;
$$;
notify pgrst,'reload schema';
