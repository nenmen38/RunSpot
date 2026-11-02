-- 조회 중심 좌표는 저장·공유하지 않으며 기존 상대 공개 범위와 차단 규칙을 유지합니다.
create function runspot_private.map_nearby_runners_at(viewer_latitude double precision,viewer_longitude double precision,radius_m integer)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz)
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
    select candidate.user_id,candidate.nickname,candidate.latitude,candidate.longitude,candidate.distance_m,candidate.updated_at
    from (
      select l.user_id,p.nickname,l.latitude,l.longitude,l.updated_at,
        6371000*acos(least(1.0,greatest(-1.0,
          sin(radians(map_nearby_runners_at.viewer_latitude))*sin(radians(l.latitude))+
          cos(radians(map_nearby_runners_at.viewer_latitude))*cos(radians(l.latitude))*
          cos(radians(l.longitude-map_nearby_runners_at.viewer_longitude))))) as distance_m
      from runspot_private.live_locations l join public.profiles p on p.id=l.user_id
      where l.updated_at>now()-interval '2 minutes' and p.nickname is not null
        and runspot_private.can_view_location(l.user_id)
    ) candidate where candidate.distance_m<=radius_m
    order by candidate.distance_m,candidate.user_id limit 200;
end;
$$;
create function public.map_nearby_runners_at(viewer_latitude double precision,viewer_longitude double precision,radius_m integer default 1000)
returns table(user_id uuid,nickname text,latitude double precision,longitude double precision,
  distance_m double precision,updated_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select * from runspot_private.map_nearby_runners_at(viewer_latitude,viewer_longitude,radius_m);
$$;
revoke all on function runspot_private.map_nearby_runners_at(double precision,double precision,integer),
  public.map_nearby_runners_at(double precision,double precision,integer) from public,anon,authenticated;
grant execute on function runspot_private.map_nearby_runners_at(double precision,double precision,integer),
  public.map_nearby_runners_at(double precision,double precision,integer) to authenticated;
notify pgrst,'reload schema';
