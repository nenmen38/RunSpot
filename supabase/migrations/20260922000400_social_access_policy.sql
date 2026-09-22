-- 개인 기능 이용과 전화번호 인증을 분리합니다.
create or replace function runspot_private.is_active(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from runspot_private.account_controls where user_id=target and status='active');
$$;
create function runspot_private.can_interact()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and runspot_private.is_active(auth.uid())
    and runspot_private.phone_verified(auth.uid());
$$;
revoke all on function runspot_private.can_interact() from public, anon, authenticated;
grant execute on function runspot_private.can_interact() to authenticated;

-- 인증 해제 또는 번호 변경 시 공개 설정도 즉시 비공개로 되돌립니다.
update public.profiles set visibility='private' where not runspot_private.phone_verified(id);
create function runspot_private.enforce_visibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility <> 'private' and not runspot_private.phone_verified(new.id) then
    raise exception '전화번호 인증 후 공개 범위를 변경할 수 있습니다.' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function runspot_private.enforce_visibility() from public, anon, authenticated;
create trigger require_phone_for_visibility before insert or update on public.profiles
for each row execute function runspot_private.enforce_visibility();
create function runspot_private.reset_unverified_visibility()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not runspot_private.phone_verified(new.id) then
    update public.profiles set visibility='private' where id=new.id and visibility<>'private';
  end if;
  return new;
end;
$$;
revoke all on function runspot_private.reset_unverified_visibility() from public, anon, authenticated;
create trigger reset_phone_visibility after update of phone,phone_confirmed_at,phone_change on auth.users
for each row execute function runspot_private.reset_unverified_visibility();

-- 게시물의 공개 범위는 작성자의 위치 공개 범위와 독립적입니다.
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated
using (runspot_private.can_read(user_id,visibility));

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index comments_post_time on public.comments(post_id,created_at);
alter table public.comments enable row level security;
revoke all on public.comments from public,anon,authenticated;
grant select on public.comments to authenticated;
grant insert(post_id,body), update(body), delete on public.comments to authenticated;
grant all on public.comments to service_role;
create policy comments_read on public.comments for select to authenticated
using (runspot_private.can_read(user_id,'public') and exists(select 1 from public.posts p where p.id=post_id));
create policy comments_insert on public.comments for insert to authenticated
with check (user_id=auth.uid() and runspot_private.can_interact()
  and exists(select 1 from public.posts p where p.id=post_id));
create policy comments_update on public.comments for update to authenticated
using (user_id=auth.uid() and runspot_private.can_interact())
with check (user_id=auth.uid() and runspot_private.can_interact()
  and exists(select 1 from public.posts p where p.id=post_id));
create policy comments_delete on public.comments for delete to authenticated
using (user_id=auth.uid() and runspot_private.is_active(auth.uid()));

-- 거리와 기록 소유권을 클라이언트 입력으로 받지 않습니다.
create function runspot_private.publish_run(target_run uuid, content text, audience text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if not runspot_private.can_interact() then
    raise exception '전화번호 인증이 필요합니다.' using errcode='42501';
  end if;
  insert into public.posts(run_id,user_id,caption,visibility,distance_m,duration_sec)
  select id,user_id,content,audience,distance_m,duration_sec from public.runs
  where id=target_run and user_id=auth.uid() and integrity_status='verified'
  returning id into result;
  if result is null then raise exception '공유할 수 없는 기록입니다.' using errcode='42501'; end if;
  return result;
end;
$$;
revoke all on function runspot_private.publish_run(uuid,text,text) from public,anon,authenticated;
grant execute on function runspot_private.publish_run(uuid,text,text) to authenticated;
create function public.publish_run(target_run uuid, content text, audience text default 'public')
returns uuid language sql security invoker set search_path = '' as $$
  select runspot_private.publish_run(target_run,content,audience);
$$;
revoke all on function public.publish_run(uuid,text,text) from public,anon,authenticated;
grant execute on function public.publish_run(uuid,text,text) to authenticated;
grant update(caption,visibility) on public.posts to authenticated;
create policy posts_update on public.posts for update to authenticated
using (user_id=auth.uid() and runspot_private.can_interact())
with check (user_id=auth.uid() and runspot_private.can_interact());

create function runspot_private.can_view_location(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select target<>auth.uid() and runspot_private.can_interact()
    and runspot_private.phone_verified(target)
    and exists (
      select 1 from public.profiles viewer, public.profiles subject
      where viewer.id=auth.uid() and subject.id=target
        and viewer.visibility<>'private' and subject.visibility<>'private'
        and runspot_private.can_read(target,subject.visibility)
        and (viewer.visibility='public' or exists (
          select 1 from public.friendships f where f.user_low=least(auth.uid(),target)
            and f.user_high=greatest(auth.uid(),target) and f.status='accepted'
        ))
    );
$$;
revoke all on function runspot_private.can_view_location(uuid) from public,anon,authenticated;
grant execute on function runspot_private.can_view_location(uuid) to authenticated;
drop policy share_paths_read on public.run_share_paths;
create policy share_paths_read on public.run_share_paths for select to authenticated
using (exists(select 1 from public.posts p where p.id=post_id
  and (p.user_id=auth.uid() or runspot_private.can_view_location(p.user_id))));

-- 위치 원본은 서버만 기록하며 앱은 범위가 제한된 조회 함수만 호출합니다.
create table runspot_private.live_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  updated_at timestamptz not null default now()
);
alter table runspot_private.live_locations enable row level security;
revoke all on runspot_private.live_locations from public,anon,authenticated;
grant select,insert,update,delete on runspot_private.live_locations to service_role;
create function runspot_private.nearby_locations(radius_m integer)
returns table(user_id uuid, latitude double precision, longitude double precision)
language plpgsql stable security definer set search_path = '' as $$
begin
  if radius_m is null or radius_m not between 1 and 5000 then
    raise exception '조회 반경은 1~5000미터입니다.' using errcode='22023';
  end if;
  return query
  select other.user_id,other.latitude,other.longitude
  from runspot_private.live_locations mine,runspot_private.live_locations other
  where mine.user_id=auth.uid()
    and mine.updated_at>now()-interval '2 minutes'
    and other.updated_at>now()-interval '2 minutes'
    and runspot_private.can_view_location(other.user_id)
    and 6371000*acos(least(1.0,greatest(-1.0,
      sin(radians(mine.latitude))*sin(radians(other.latitude))+
      cos(radians(mine.latitude))*cos(radians(other.latitude))*
      cos(radians(other.longitude-mine.longitude)))))<=radius_m
  order by other.user_id limit 200;
end;
$$;
revoke all on function runspot_private.nearby_locations(integer) from public,anon,authenticated;
grant execute on function runspot_private.nearby_locations(integer) to authenticated;
create function public.nearby_locations(radius_m integer default 1000)
returns table(user_id uuid,latitude double precision,longitude double precision)
language sql stable security invoker set search_path = '' as $$
  select * from runspot_private.nearby_locations(radius_m);
$$;
revoke all on function public.nearby_locations(integer) from public,anon,authenticated;
grant execute on function public.nearby_locations(integer) to authenticated;
