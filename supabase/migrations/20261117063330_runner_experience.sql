-- 목표 설정은 로그인한 계정에만 연결합니다.
create table runspot_private.weekly_goals (
 user_id uuid primary key references auth.users(id) on delete cascade,
 kilometers integer check(kilometers between 1 and 500),
 updated_at timestamptz not null default now()
);
alter table runspot_private.weekly_goals enable row level security;
revoke all on runspot_private.weekly_goals from public,anon,authenticated;
create function runspot_private.my_weekly_goal(update_goal boolean default false,kilometers integer default null)
returns integer language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid();
begin
 if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 if update_goal then
   if kilometers is not null and kilometers not between 1 and 500 then raise exception '목표는 1~500km로 설정해 주세요.' using errcode='22023'; end if;
   insert into runspot_private.weekly_goals as g(user_id,kilometers) values(viewer,my_weekly_goal.kilometers)
   on conflict(user_id) do update set kilometers=excluded.kilometers,updated_at=now();
 end if;
 return (select g.kilometers from runspot_private.weekly_goals g where g.user_id=viewer);
end;
$$;
create function public.my_weekly_goal(update_goal boolean default false,kilometers integer default null)
returns integer language sql security invoker set search_path='' as $$
 select runspot_private.my_weekly_goal(update_goal,kilometers);
$$;
revoke all on function public.my_weekly_goal(boolean,integer),runspot_private.my_weekly_goal(boolean,integer) from public,anon,authenticated;
grant execute on function public.my_weekly_goal(boolean,integer),runspot_private.my_weekly_goal(boolean,integer) to authenticated;
notify pgrst,'reload schema';
