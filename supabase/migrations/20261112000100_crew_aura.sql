-- 함께 달릴 때 오라가 합쳐지는 효과를 위해 주변 러너의 착용 테두리·색과 친구의 현재 페이스를 함께 돌려줍니다.
-- 위치 공개 규칙(can_view_location)은 그대로이며, 이전 앱은 늘어난 항목을 무시하고 그대로 동작합니다.
alter table runspot_private.live_locations
  add column pace_sec integer check (pace_sec between 120 and 1800);

-- 페이스(초/km)는 선택 항목입니다. 범위를 벗어난 값은 저장하지 않습니다.
drop function public.update_my_live_location(double precision,double precision,double precision);
drop function runspot_private.update_my_live_location(double precision,double precision,double precision);
create function runspot_private.update_my_live_location(
  latitude double precision, longitude double precision, accuracy_m double precision, pace_sec_per_km integer
) returns void language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  previous_update timestamptz;
  pace_value integer := case when pace_sec_per_km between 120 and 1800 then pace_sec_per_km end;
begin
  if owner_id is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
  -- 계정과 공개 설정을 잠근 뒤 인증 및 공개 범위를 검사합니다.
  perform 1 from auth.users where id=owner_id for update;
  perform 1 from public.profiles where id=owner_id for update;
  if owner_id is null or not runspot_private.can_interact() or not exists (
    select 1 from public.profiles where id=owner_id and visibility<>'private'
  ) then
    raise exception '이메일 인증과 닉네임 등록 후 프로필을 친구 또는 전체 공개로 설정해 주세요.'
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
  insert into runspot_private.live_locations(user_id,latitude,longitude,updated_at,pace_sec)
    values(owner_id,latitude,longitude,clock_timestamp(),pace_value)
    on conflict(user_id) do update set latitude=excluded.latitude,
      longitude=excluded.longitude,updated_at=excluded.updated_at,pace_sec=excluded.pace_sec;
end;
$$;
create function public.update_my_live_location(
  latitude double precision, longitude double precision, accuracy_m double precision,
  pace_sec_per_km integer default null
) returns void language sql security invoker set search_path = '' as $$
  select runspot_private.update_my_live_location(latitude,longitude,accuracy_m,pace_sec_per_km);
$$;

-- 테두리와 색은 지도에 보이는 모든 러너에게, 친구 여부와 페이스는 친구에게만 돌려줍니다.
drop function public.map_nearby_runners_at(double precision,double precision,integer);
drop function runspot_private.map_nearby_runners_at(double precision,double precision,integer);
create function runspot_private.map_nearby_runners_at(viewer_latitude double precision,viewer_longitude double precision,radius_m integer)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz,is_friend boolean,frame text,frame_color text,pace_sec integer)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if viewer_latitude is null or viewer_latitude not between -90 and 90
    or viewer_longitude is null or viewer_longitude not between -180 and 180
    or radius_m is null or radius_m not between 1 and 5000 then
    raise exception '조회 위치와 반경을 확인해 주세요.' using errcode='22023';
  end if;
  return query
    select candidate.user_id,candidate.nickname,candidate.latitude,candidate.longitude,candidate.distance_m,
      candidate.updated_at,candidate.is_friend,s.frame,case when s.frame is not null then s.color end,
      case when candidate.is_friend then candidate.pace_sec end
    from (
      select l.user_id,p.nickname,l.latitude,l.longitude,l.updated_at,l.pace_sec,
        exists(select 1 from public.friendships f where f.user_low=least(auth.uid(),l.user_id)
          and f.user_high=greatest(auth.uid(),l.user_id) and f.status='accepted') as is_friend,
        6371000*acos(least(1.0,greatest(-1.0,
          sin(radians(map_nearby_runners_at.viewer_latitude))*sin(radians(l.latitude))+
          cos(radians(map_nearby_runners_at.viewer_latitude))*cos(radians(l.latitude))*
          cos(radians(l.longitude-map_nearby_runners_at.viewer_longitude))))) as distance_m
      from runspot_private.live_locations l join public.profiles p on p.id=l.user_id
      where l.updated_at>now()-interval '2 minutes' and p.nickname is not null
        and runspot_private.can_view_location(l.user_id)
    ) candidate
    left join runspot_private.frame_settings s on s.user_id=candidate.user_id
    where candidate.distance_m<=radius_m
    order by candidate.distance_m,candidate.user_id limit 200;
end;
$$;
create function public.map_nearby_runners_at(viewer_latitude double precision,viewer_longitude double precision,radius_m integer default 1000)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz,is_friend boolean,frame text,frame_color text,pace_sec integer)
language sql stable security invoker set search_path='' as $$
  select * from runspot_private.map_nearby_runners_at(viewer_latitude,viewer_longitude,radius_m);
$$;

revoke all on function
  runspot_private.update_my_live_location(double precision,double precision,double precision,integer),
  public.update_my_live_location(double precision,double precision,double precision,integer),
  runspot_private.map_nearby_runners_at(double precision,double precision,integer),
  public.map_nearby_runners_at(double precision,double precision,integer) from public,anon,authenticated;
grant execute on function
  runspot_private.update_my_live_location(double precision,double precision,double precision,integer),
  public.update_my_live_location(double precision,double precision,double precision,integer),
  runspot_private.map_nearby_runners_at(double precision,double precision,integer),
  public.map_nearby_runners_at(double precision,double precision,integer) to authenticated;
notify pgrst,'reload schema';
