-- 좌표 원본을 노출하지 않고 본인 위치만 서버 함수로 갱신합니다.
create function runspot_private.update_my_live_location(
  latitude double precision, longitude double precision, accuracy_m double precision
) returns void language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  previous_update timestamptz;
begin
  if owner_id is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  -- 계정과 공개 설정을 잠근 뒤 인증 및 공개 범위를 검사합니다.
  perform 1 from auth.users where id=owner_id for update;
  perform 1 from public.profiles where id=owner_id for update;
  if owner_id is null or not runspot_private.can_interact() or not exists (
    select 1 from public.profiles where id=owner_id and visibility<>'private'
  ) then
    raise exception '전화번호 인증과 닉네임 등록 후 프로필을 친구 또는 전체 공개로 설정해 주세요.'
      using errcode='42501';
  end if;
  if latitude is null or longitude is null or accuracy_m is null
    or not latitude between -90 and 90 or not longitude between -180 and 180
    or not accuracy_m between 0 and 100 then
    raise exception '정확한 현재 위치가 필요합니다.' using errcode='22023';
  end if;
  -- 계정별로 직렬화하여 동시 요청도 갱신 간격 제한을 지킵니다.
  select updated_at into previous_update from runspot_private.live_locations where user_id=owner_id;
  if previous_update > clock_timestamp()-interval '3 seconds' then return; end if;
  insert into runspot_private.live_locations(user_id,latitude,longitude,updated_at)
    values(owner_id,latitude,longitude,clock_timestamp())
    on conflict(user_id) do update set latitude=excluded.latitude,
      longitude=excluded.longitude,updated_at=excluded.updated_at;
end;
$$;

create function public.update_my_live_location(
  latitude double precision, longitude double precision, accuracy_m double precision
) returns void language sql security invoker set search_path = '' as $$
  select runspot_private.update_my_live_location(latitude,longitude,accuracy_m);
$$;

create function runspot_private.stop_live_location()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  perform 1 from auth.users where id=auth.uid() for update;
  delete from runspot_private.live_locations where user_id=auth.uid();
end;
$$;
create function public.stop_live_location()
returns void language sql security invoker set search_path = '' as $$
  select runspot_private.stop_live_location();
$$;

create function runspot_private.map_nearby_runners(radius_m integer)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select nearby.user_id,profile.nickname,nearby.latitude,nearby.longitude,
    6371000*acos(least(1.0,greatest(-1.0,
      sin(radians(mine.latitude))*sin(radians(nearby.latitude))+
      cos(radians(mine.latitude))*cos(radians(nearby.latitude))*
      cos(radians(nearby.longitude-mine.longitude))))),other.updated_at
  from runspot_private.nearby_locations(radius_m) nearby
  join public.profiles profile on profile.id=nearby.user_id and profile.nickname is not null
  join runspot_private.live_locations other on other.user_id=nearby.user_id
  join runspot_private.live_locations mine on mine.user_id=auth.uid()
  order by 5,nearby.user_id;
$$;
create function public.map_nearby_runners(radius_m integer default 1000)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select * from runspot_private.map_nearby_runners(radius_m);
$$;

revoke all on function runspot_private.update_my_live_location(double precision,double precision,double precision),
  runspot_private.stop_live_location(),runspot_private.map_nearby_runners(integer),
  public.update_my_live_location(double precision,double precision,double precision),
  public.stop_live_location(),public.map_nearby_runners(integer) from public,anon,authenticated;
grant execute on function runspot_private.update_my_live_location(double precision,double precision,double precision),
  runspot_private.stop_live_location(),runspot_private.map_nearby_runners(integer),
  public.update_my_live_location(double precision,double precision,double precision),
  public.stop_live_location(),public.map_nearby_runners(integer) to authenticated;

-- 비공개 좌표 대신 빈 변경 신호만 방송하고 조회 때마다 공개 범위와 차단을 재검사합니다.
create function runspot_private.notify_runner_map()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform realtime.send('{}'::jsonb,'changed','runner-map',true);
  return null;
end;
$$;
revoke all on function runspot_private.notify_runner_map() from public,anon,authenticated;
create trigger live_runner_map_changed after insert or update or delete on runspot_private.live_locations
for each statement execute function runspot_private.notify_runner_map();
create trigger runner_map_privacy_changed after update of visibility,nickname on public.profiles
for each statement execute function runspot_private.notify_runner_map();
create trigger runner_map_blocks_changed after insert or delete on runspot_private.blocks
for each statement execute function runspot_private.notify_runner_map();
create trigger runner_map_friendships_changed after insert or update or delete on public.friendships
for each statement execute function runspot_private.notify_runner_map();
create trigger runner_map_account_changed after update of status on runspot_private.account_controls
for each statement execute function runspot_private.notify_runner_map();

-- 공개 해제 시 원본도 제거하여 다시 공개해도 이전 위치가 살아나지 않습니다.
create function runspot_private.clear_hidden_live_location()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility='private' or new.nickname is null then
    delete from runspot_private.live_locations where user_id=new.id;
  end if;
  return new;
end;
$$;
revoke all on function runspot_private.clear_hidden_live_location() from public,anon,authenticated;
create trigger clear_hidden_live_location after update of visibility,nickname on public.profiles
for each row execute function runspot_private.clear_hidden_live_location();

-- 클라이언트에는 변경 신호 수신만 허용하며 방송 전송 권한을 부여하지 않습니다.
create policy runner_map_broadcast_read on realtime.messages for select to authenticated
using (realtime.topic()='runner-map' and extension='broadcast' and runspot_private.can_interact());
