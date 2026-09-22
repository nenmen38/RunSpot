-- 권한이 없는 클라이언트는 기본적으로 어떤 데이터도 변경할 수 없습니다.
create schema runspot_private;
revoke all on schema runspot_private from public, anon, authenticated;
grant usage on schema runspot_private to authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text check (char_length(nickname) between 2 and 30),
  display_name text not null default '' check (char_length(display_name) <= 60),
  visibility text not null default 'private' check (visibility in ('private','friends','public')),
  created_at timestamptz not null default now()
);
create unique index profiles_nickname_unique on public.profiles (lower(nickname));

create table runspot_private.account_controls (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','suspended','deleting')),
  updated_at timestamptz not null default now()
);
create table runspot_private.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('moderator','admin')),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now()
);
create table runspot_private.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique check (char_length(token) between 1 and 4096),
  platform text not null check (platform in ('android','ios','web')),
  last_seen_at timestamptz not null default now()
);
create index user_devices_owner on runspot_private.user_devices(user_id);

create table public.friendships (
  user_low uuid not null references auth.users(id) on delete cascade,
  user_high uuid not null references auth.users(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key(user_low,user_high),
  check (user_low < user_high),
  check (requested_by in (user_low,user_high))
);
create index friendships_high on public.friendships(user_high,user_low);
create table runspot_private.blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  primary key(blocker_id,blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_reverse on runspot_private.blocks(blocked_id,blocker_id);

create table public.route_presets (
  code text primary key,
  name text not null,
  distance_m integer not null check (distance_m > 0),
  slope text not null check (slope in ('flat','gentle','uphill')),
  flow text not null check (flow in ('pace','relaxed','few_signals')),
  environment text not null check (environment in ('urban','nature','mixed')),
  safety text not null check (safety in ('optimal','avoid_alleys','night'))
);
-- 실제 경로는 별도의 비공개 객체에 보관하며 이 테이블에는 위치를 넣지 않습니다.
create table public.routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  preset_code text references public.route_presets(code),
  title text not null check (char_length(title) between 1 and 120),
  distance_m integer not null check (distance_m > 0),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);
create index routes_owner on public.routes(user_id,created_at desc);
create table runspot_private.route_tracks (
  route_id uuid primary key references public.routes(id) on delete cascade,
  object_path text not null unique
);
create table public.runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_run_id uuid not null,
  route_id uuid,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_m integer not null check (distance_m > 0),
  duration_sec integer not null check (duration_sec > 0),
  elevation_gain_m integer not null default 0 check (elevation_gain_m >= 0),
  integrity_status text not null default 'pending' check (integrity_status in ('pending','verified','rejected')),
  created_at timestamptz not null default now(),
  unique(user_id,client_run_id),
  unique(id,user_id),
  foreign key(route_id,user_id) references public.routes(id,user_id),
  check (ended_at > started_at),
  check (duration_sec <= extract(epoch from ended_at-started_at) + 1)
);
create index runs_owner_time on public.runs(user_id,started_at desc);
create table public.run_splits (
  run_id uuid not null references public.runs(id) on delete cascade,
  split_index integer not null check (split_index >= 0),
  distance_m integer not null check (distance_m > 0),
  duration_sec integer not null check (duration_sec > 0),
  primary key(run_id,split_index)
);
create table runspot_private.run_tracks (
  run_id uuid primary key references public.runs(id) on delete cascade,
  object_path text not null unique,
  sample_count integer not null check (sample_count > 0),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  delete_after timestamptz
);
-- 공개용 기록에는 원본의 시작 시각이나 좌표를 포함하지 않습니다.
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 2000),
  visibility text not null default 'private' check (visibility in ('private','friends','public')),
  distance_m integer not null check (distance_m > 0),
  duration_sec integer not null check (duration_sec > 0),
  created_at timestamptz not null default now(),
  foreign key(run_id,user_id) references public.runs(id,user_id) on delete cascade
);
create index posts_owner_time on public.posts(user_id,created_at desc);
create table public.run_share_paths (
  post_id uuid primary key references public.posts(id) on delete cascade,
  encoded_polyline text not null check (char_length(encoded_polyline) <= 200000),
  sanitizer_version text not null,
  created_at timestamptz not null default now()
);

create table public.achievement_definitions (
  code text primary key,
  title text not null,
  metric text not null check (metric in ('distinct_routes','night_runs','elevation_m')),
  target integer not null check (target > 0)
);
create table public.user_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_code text not null references public.achievement_definitions(code),
  progress integer not null default 0 check (progress >= 0),
  achieved_at timestamptz,
  primary key(user_id,achievement_code)
);
create table runspot_private.integrity_cases (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references public.runs(id) on delete cascade,
  rule_code text not null,
  risk_score smallint not null check (risk_score between 0 and 100),
  status text not null default 'open' check (status in ('open','evidence_requested','approved','rejected')),
  assigned_to uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table runspot_private.integrity_actions (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references runspot_private.integrity_cases(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  note text not null default '' check (char_length(note) <= 2000),
  created_at timestamptz not null default now()
);
create table runspot_private.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  target_id uuid,
  created_at timestamptz not null default now()
);
create table runspot_private.ai_usage (
  request_id uuid primary key,
  user_id uuid references auth.users(id) on delete set null,
  feature text not null,
  model text not null,
  input_tokens integer not null check (input_tokens >= 0),
  output_tokens integer not null check (output_tokens >= 0),
  created_at timestamptz not null default now()
);
create table public.run_feedback (
  run_id uuid primary key references public.runs(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 500),
  source text not null check (source in ('rules','ai')),
  version text not null,
  created_at timestamptz not null default now()
);

create function runspot_private.is_active(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.account_controls where user_id=target and status='active');
$$;
create function runspot_private.can_read(owner_id uuid, visibility text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and runspot_private.is_active(auth.uid())
    and (owner_id=auth.uid() or (
      runspot_private.is_active(owner_id)
      and not exists(select 1 from runspot_private.blocks b
        where (b.blocker_id=auth.uid() and b.blocked_id=owner_id)
           or (b.blocked_id=auth.uid() and b.blocker_id=owner_id))
      and (visibility='public' or (visibility='friends' and exists(
        select 1 from public.friendships f where f.user_low=least(owner_id,auth.uid())
        and f.user_high=greatest(owner_id,auth.uid()) and f.status='accepted'
      )))
    ));
$$;
create function runspot_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values(new.id);
  insert into runspot_private.account_controls(user_id) values(new.id);
  return new;
end;
$$;
create trigger runspot_new_user after insert on auth.users
for each row execute function runspot_private.create_profile();
-- 기존 사용자의 인증 메타데이터를 권한으로 복사하지 않습니다.
insert into public.profiles(id) select id from auth.users;
insert into runspot_private.account_controls(user_id) select id from auth.users;

revoke all on all functions in schema runspot_private from public, anon, authenticated;
grant execute on function runspot_private.is_active(uuid), runspot_private.can_read(uuid,text) to authenticated;

-- 토큰에 남아 있는 이전 역할 대신 현재 역할과 다중 인증 여부를 검사합니다.
create function runspot_private.staff_role()
returns text language sql stable security definer set search_path = '' as $$
  select role from runspot_private.user_roles
  where user_id=auth.uid() and runspot_private.is_active(auth.uid())
    and auth.jwt()->>'aal'='aal2';
$$;
revoke all on function runspot_private.staff_role() from public, anon, authenticated;
grant execute on function runspot_private.staff_role() to authenticated;
create function public.my_staff_role()
returns text language sql stable security invoker set search_path = '' as $$
  select runspot_private.staff_role();
$$;
revoke all on function public.my_staff_role() from public, anon, authenticated;
grant execute on function public.my_staff_role() to authenticated;

-- 이 마이그레이션에서 생성한 테이블에만 권한을 적용합니다.
do $$
declare t text;
begin
  foreach t in array array['profiles','friendships','route_presets','routes','runs','run_splits','posts','run_share_paths','achievement_definitions','user_achievements','run_feedback'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('grant all on public.%I to service_role',t);
  end loop;
end;
$$;
do $$
declare t text;
begin
  foreach t in array array['account_controls','user_roles','user_devices','blocks','route_tracks','run_tracks','integrity_cases','integrity_actions','audit_logs','ai_usage'] loop
    execute format('alter table runspot_private.%I enable row level security',t);
    execute format('revoke all on runspot_private.%I from public, anon, authenticated',t);
    execute format('grant select, insert, update, delete on runspot_private.%I to service_role',t);
  end loop;
end;
$$;
grant usage on sequence runspot_private.audit_logs_id_seq to service_role;
revoke update, delete on runspot_private.audit_logs from service_role;
revoke update, delete on runspot_private.integrity_actions from service_role;

create policy profiles_read on public.profiles for select to authenticated
using (runspot_private.can_read(id,visibility));
grant update(nickname,display_name,visibility) on public.profiles to authenticated;
create policy profiles_update on public.profiles for update to authenticated
using (id=(select auth.uid()) and runspot_private.is_active((select auth.uid())))
with check (id=(select auth.uid()) and runspot_private.is_active((select auth.uid())));
create policy friendships_read on public.friendships for select to authenticated
using ((select auth.uid()) in (user_low,user_high) and runspot_private.is_active((select auth.uid())));
create policy presets_read on public.route_presets for select to authenticated
using (runspot_private.is_active((select auth.uid())));
create policy routes_read on public.routes for select to authenticated
using (runspot_private.can_read(user_id,'private'));
create policy runs_read on public.runs for select to authenticated
using (runspot_private.can_read(user_id,'private'));
create policy splits_read on public.run_splits for select to authenticated
using (exists(select 1 from public.runs r where r.id=run_id));
create policy posts_read on public.posts for select to authenticated
using (runspot_private.can_read(user_id,visibility)
  and exists(select 1 from public.profiles p where p.id=user_id));
create policy share_paths_read on public.run_share_paths for select to authenticated
using (exists(select 1 from public.posts p where p.id=post_id));
create policy definitions_read on public.achievement_definitions for select to authenticated
using (runspot_private.is_active((select auth.uid())));
create policy achievements_read on public.user_achievements for select to authenticated
using (exists(select 1 from public.profiles p where p.id=user_id));
create policy feedback_read on public.run_feedback for select to authenticated
using (exists(select 1 from public.runs r where r.id=run_id));
