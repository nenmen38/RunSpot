-- 내 코스: 달린 기록의 경로를 이름을 붙여 저장해 두고, 다음에 지도에 점선 안내선으로 띄워 같은 길을 달립니다.
-- 경로 원본(measured_run_routes)은 서버에서만 복사하고, 지도에 그리기 좋게 400개 안팎의 점으로 줄여 저장합니다.
create table runspot_private.saved_courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  run_id uuid references public.runs(id) on delete set null,
  name text not null check (length(btrim(name)) between 1 and 30),
  distance_m integer not null check (distance_m > 0),
  segments jsonb not null check (jsonb_typeof(segments) = 'array'),
  created_at timestamptz not null default now()
);
create index saved_courses_owner on runspot_private.saved_courses(user_id, created_at desc);
alter table runspot_private.saved_courses enable row level security;
revoke all on runspot_private.saved_courses from public, anon, authenticated;

create function runspot_private.course_json(c runspot_private.saved_courses)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'distance_m', c.distance_m,
    'segments', c.segments, 'created_at', c.created_at);
$$;
revoke all on function runspot_private.course_json(runspot_private.saved_courses) from public, anon, authenticated;

-- 내 기록 하나를 코스로 저장합니다(한 사람당 30개까지).
create function runspot_private.save_course(requested_run_id uuid, course_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := runspot_private.require_board_viewer();
  route runspot_private.measured_run_routes;
  meters integer;
  step integer;
  simplified jsonb;
  saved runspot_private.saved_courses;
begin
  if course_name is null or length(btrim(course_name)) not between 1 and 30 then
    raise exception '코스 이름은 1~30자로 정해 주세요.' using errcode = '22023';
  end if;
  select r.distance_m into meters from public.runs r
    where r.id = requested_run_id and r.user_id = viewer and r.integrity_status <> 'rejected';
  select * into route from runspot_private.measured_run_routes t where t.run_id = requested_run_id;
  if meters is null or route.run_id is null or route.sample_count < 2 then
    raise exception '경로가 있는 내 기록만 코스로 저장할 수 있어요.' using errcode = 'P0001';
  end if;
  if (select count(*) from runspot_private.saved_courses where user_id = viewer) >= 30 then
    raise exception '코스는 30개까지 저장할 수 있어요. 안 쓰는 코스를 지워 주세요.' using errcode = 'P0001';
  end if;
  step := greatest(1, ceil(route.sample_count / 400.0)::integer);
  -- 구간마다 step 간격의 점과 끝점만 남깁니다.
  select coalesce(jsonb_agg(points order by seg_index), '[]'::jsonb) into simplified
  from (
    select s.seg_index, jsonb_agg(p.point order by p.point_index) as points
    from jsonb_array_elements(route.segments) with ordinality s(segment, seg_index)
    cross join lateral jsonb_array_elements(s.segment) with ordinality p(point, point_index)
    where (p.point_index - 1) % step = 0 or p.point_index = jsonb_array_length(s.segment)
    group by s.seg_index
  ) kept;
  insert into runspot_private.saved_courses(user_id, run_id, name, distance_m, segments)
    values (viewer, requested_run_id, btrim(course_name), meters, simplified)
    returning * into saved;
  return runspot_private.course_json(saved);
end;
$$;

create function runspot_private.my_courses()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  return (select coalesce(jsonb_agg(runspot_private.course_json(c) order by c.created_at desc), '[]'::jsonb)
    from runspot_private.saved_courses c where c.user_id = viewer);
end;
$$;

create function runspot_private.delete_course(course_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := runspot_private.require_board_viewer();
begin
  delete from runspot_private.saved_courses where id = course_id and user_id = viewer;
end;
$$;

create function public.save_course(requested_run_id uuid, course_name text)
returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.save_course(requested_run_id, course_name); $$;
create function public.my_courses()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.my_courses(); $$;
create function public.delete_course(course_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select runspot_private.delete_course(course_id); $$;
revoke all on function runspot_private.save_course(uuid, text), public.save_course(uuid, text),
  runspot_private.my_courses(), public.my_courses(),
  runspot_private.delete_course(uuid), public.delete_course(uuid) from public, anon, authenticated;
grant execute on function runspot_private.save_course(uuid, text), public.save_course(uuid, text),
  runspot_private.my_courses(), public.my_courses(),
  runspot_private.delete_course(uuid), public.delete_course(uuid) to authenticated;
notify pgrst, 'reload schema';
