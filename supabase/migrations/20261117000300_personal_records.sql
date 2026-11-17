-- 개인 최고 기록(1km·5km·10km)입니다. 저장한 1km 구간 기록(split_data)에서 이어 달린 구간의 가장 짧은 시간을 찾습니다.
-- 반려된 기록은 빼고, 구간 기록이 없는 예전 기록은 계산하지 않습니다.
create function runspot_private.my_personal_records()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare viewer uuid:=auth.uid();
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인이 필요합니다.' using errcode='42501';
  end if;
  return (with splits as (
      select r.id,r.started_at,s.ord,(s.v->>'duration_us')::bigint as us
      from public.runs r
      cross join lateral jsonb_array_elements(r.split_data) with ordinality s(v,ord)
      where r.user_id=viewer and r.integrity_status<>'rejected' and r.split_data is not null
        and (s.v->>'distance_m')::numeric=1000
    ), sizes(km) as (values (1),(5),(10)
    ), windows as (
      select z.km,a.id,a.started_at,sum(b.us) as us
      from sizes z join splits a on true
      join splits b on b.id=a.id and b.ord between a.ord and a.ord+z.km-1
      group by z.km,a.id,a.started_at,a.ord
      having count(*)=z.km
    ), best as (
      select distinct on (km) km,id,started_at,us from windows order by km,us,started_at
    )
    select coalesce(jsonb_agg(jsonb_build_object('distance_km',km,'duration_us',us,'run_id',id,'started_at',started_at)
      order by km),'[]'::jsonb) from best);
end;
$$;
create function public.my_personal_records()
returns jsonb language sql stable security invoker set search_path='' as $$
  select runspot_private.my_personal_records();
$$;
revoke all on function runspot_private.my_personal_records(),public.my_personal_records() from public,anon,authenticated;
grant execute on function runspot_private.my_personal_records(),public.my_personal_records() to authenticated;
notify pgrst,'reload schema';
