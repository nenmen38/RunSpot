alter table runspot_private.notifications
  add column moderation_action_id bigint unique
    references runspot_private.moderation_actions(id) on delete cascade,
  drop constraint notifications_kind_check,
  drop constraint notifications_target_check,
  add constraint notifications_kind_check check (kind in ('like','comment','reply','group_invite','crew_invite','moderation_action')),
  add constraint notifications_moderation_action_check
    check ((kind='moderation_action') = (moderation_action_id is not null)),
  add constraint notifications_target_check check (case kind
    when 'group_invite' then group_id is not null and post_id is null and crew_id is null
    when 'moderation_action' then post_id is null and group_id is null and crew_id is null
      and actor_id=recipient_id
    when 'crew_invite' then crew_id is not null and post_id is null and group_id is null
    else post_id is not null and group_id is null and crew_id is null end);

-- 신고가 확정되어 조치 이력이 생성될 때 대상자의 알림함에도 함께 기록합니다.
-- 알림의 사용자 참조는 수신자 본인으로 저장해 신고자와 처리자 정보가 노출되지 않게 합니다.
create function runspot_private.notify_moderation_action()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  insert into runspot_private.notifications(recipient_id,actor_id,kind,moderation_action_id)
  values(new.user_id,new.user_id,'moderation_action',new.id);
  return null;
end;
$$;
revoke all on function runspot_private.notify_moderation_action() from public,anon,authenticated;

create trigger moderation_actions_notify after insert on runspot_private.moderation_actions
  for each row when (new.user_id is not null)
  execute function runspot_private.notify_moderation_action();

create or replace function runspot_private.notification_visible(n runspot_private.notifications,viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when n.kind='moderation_action' then n.recipient_id=viewer
    else runspot_private.board_author_visible(n.actor_id,viewer) and case n.kind
    when 'group_invite' then exists(select 1 from runspot_private.running_group_members m
      where m.group_id=n.group_id and m.user_id=viewer)
    when 'crew_invite' then exists(select 1 from runspot_private.crew_invites i
      where i.crew_id=n.crew_id and i.user_id=viewer)
    else runspot_private.board_post_visible(n.post_id,viewer)
      and (n.kind<>'like' or exists(select 1 from runspot_private.board_likes l
        where l.post_id=n.post_id and l.user_id=n.actor_id)) end end;
$$;

create or replace function runspot_private.my_notifications()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'post_id',x.post_id,
      'post_title',p.title,'nickname',coalesce(pr.nickname,'닉네임 없음'),
      'moderation_kind',a.kind,'moderation_reason',a.reason,
      'comment',left(c.body,80),'created_at',x.created_at,'read',x.read_at is not null,
      'group_id',x.group_id,'crew_id',x.crew_id,'crew_name',cr.name,
      'invite_status',coalesce(m.status,ci.status),
      'can_respond',(x.kind='group_invite' and m.status='invited' and g.state='lobby' and g.expires_at>now())
        or (x.kind='crew_invite' and ci.status='invited'))
      order by x.created_at desc,x.id desc),'[]'::jsonb)
    from (select * from runspot_private.notifications n where n.recipient_id=viewer
      and runspot_private.notification_visible(n,viewer) order by n.created_at desc,n.id desc limit 50) x
    left join runspot_private.board_posts p on p.id=x.post_id
    left join runspot_private.board_comments c on c.id=x.comment_id
    left join runspot_private.running_groups g on g.id=x.group_id
    left join runspot_private.running_group_members m on m.group_id=x.group_id and m.user_id=viewer
    left join runspot_private.crews cr on cr.id=x.crew_id
    left join runspot_private.crew_invites ci on ci.crew_id=x.crew_id and ci.user_id=viewer
    left join runspot_private.moderation_actions a on a.id=x.moderation_action_id and a.user_id=viewer
    left join public.profiles pr on pr.id=x.actor_id);
end;
$$;
