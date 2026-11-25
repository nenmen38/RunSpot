-- 가입 시 표시한 커뮤니티 정책의 버전과 동의 시각을 서버에 기록합니다.
create table runspot_private.community_policy_consents (
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version integer not null check (policy_version > 0),
  accepted_at timestamptz not null default now(),
  primary key (user_id, policy_version)
);
alter table runspot_private.community_policy_consents enable row level security;
revoke all on runspot_private.community_policy_consents from public, anon, authenticated;

create function runspot_private.community_policy_version()
returns integer language sql immutable set search_path = '' as $$ select 1; $$;
revoke all on function runspot_private.community_policy_version() from public, anon, authenticated;

create function runspot_private.has_community_policy_consent(viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from runspot_private.community_policy_consents
    where user_id = viewer and policy_version = runspot_private.community_policy_version()
  );
$$;
revoke all on function runspot_private.has_community_policy_consent(uuid) from public, anon, authenticated;

create function public.my_community_policy_accepted()
returns boolean language sql stable security definer set search_path = '' as $$
  select runspot_private.has_community_policy_consent(auth.uid());
$$;

create function public.accept_community_policy(shown_version integer)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
  if viewer is null or not exists (
    select 1 from auth.sessions where id = (auth.jwt()->>'session_id')::uuid and user_id = viewer
  ) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode = '42501';
  end if;
  if shown_version is distinct from runspot_private.community_policy_version() then
    raise exception '최신 앱에서 운영정책을 확인해 주세요.' using errcode = '22023';
  end if;

  insert into runspot_private.community_policy_consents (user_id, policy_version)
  values (viewer, shown_version)
  on conflict do nothing;
end;
$$;
revoke all on function public.my_community_policy_accepted(), public.accept_community_policy(integer)
from public, anon, authenticated;
grant execute on function public.my_community_policy_accepted(), public.accept_community_policy(integer)
to authenticated;

-- 이전 앱에서 RPC를 호출해도 동의 없이 게시물이나 메시지를 만들 수 없습니다.
create function runspot_private.require_community_policy()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not runspot_private.has_community_policy_consent(auth.uid()) then
    raise exception '커뮤니티 운영정책에 먼저 동의해 주세요.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function runspot_private.require_community_policy() from public, anon, authenticated;

create trigger board_post_community_policy
before insert or update of title, body, image_paths on runspot_private.board_posts
for each row execute function runspot_private.require_community_policy();

create trigger board_comment_community_policy
before insert or update of body on runspot_private.board_comments
for each row execute function runspot_private.require_community_policy();

create trigger friend_message_community_policy
before insert on runspot_private.friend_messages
for each row execute function runspot_private.require_community_policy();

create trigger room_message_community_policy
before insert on runspot_private.chat_room_messages
for each row execute function runspot_private.require_community_policy();

create trigger avatar_community_policy
before insert or update of photo on runspot_private.profile_avatars
for each row execute function runspot_private.require_community_policy();

create policy community_policy_upload on storage.objects as restrictive
for insert to authenticated
with check (
  bucket_id <> 'board-images'
  or public.my_community_policy_accepted()
);

notify pgrst, 'reload schema';
