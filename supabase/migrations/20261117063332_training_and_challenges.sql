-- 훈련 일정과 기록 연결은 본인만 관리하며 순위·보상에는 영향을 주지 않습니다.
create table runspot_private.training_plans(
 user_id uuid primary key references auth.users(id) on delete cascade,
 start_day date not null, kind text not null check(kind in ('habit','5k','10k')),
 created_at timestamptz not null default now()
);
create table runspot_private.training_completions(
 user_id uuid references runspot_private.training_plans(user_id) on delete cascade,
 session_index integer check(session_index between 0 and 11),
 run_id uuid not null references public.runs(id) on delete cascade,
 primary key(user_id,session_index), unique(user_id,run_id)
);
alter table runspot_private.training_plans enable row level security;
alter table runspot_private.training_completions enable row level security;
revoke all on runspot_private.training_plans,runspot_private.training_completions from public,anon,authenticated;
create function runspot_private.training_plan(operation text default 'read',kind text default null,start_day date default null,session_index integer default null,run_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); p runspot_private.training_plans;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('training:'||viewer::text,0));
 if operation='start' then
   if kind is null or kind not in ('habit','5k','10k') or start_day is null or start_day<current_date-30 or start_day>current_date+90 then raise exception '계획과 시작일을 확인해 주세요.' using errcode='22023'; end if;
   delete from runspot_private.training_plans where user_id=viewer;
   insert into runspot_private.training_plans(user_id,kind,start_day) values(viewer,kind,start_day);
 elsif operation='stop' then delete from runspot_private.training_plans where user_id=viewer;
 elsif operation='complete' then
   select * into p from runspot_private.training_plans where user_id=viewer;
   if not found or session_index is null or session_index not between 0 and 11 then raise exception '훈련 회차를 확인해 주세요.' using errcode='22023'; end if;
   if not exists(select 1 from public.runs r where r.id=training_plan.run_id and r.user_id=viewer and (r.started_at at time zone 'Asia/Seoul')::date>=p.start_day and r.duration_sec>0) then raise exception '계획 시작 이후 본인 기록을 선택해 주세요.' using errcode='42501'; end if;
   insert into runspot_private.training_completions(user_id,session_index,run_id) values(viewer,session_index,run_id)
     on conflict(user_id,session_index) do update set run_id=excluded.run_id;
 elsif operation='undo' then delete from runspot_private.training_completions c where c.user_id=viewer and c.session_index=training_plan.session_index;
 elsif operation<>'read' or operation is null then raise exception '지원하지 않는 훈련 작업입니다.' using errcode='22023'; end if;
 return (select to_jsonb(t)||jsonb_build_object('completed',(select coalesce(jsonb_agg(jsonb_build_object('index',c.session_index,'run_id',c.run_id)),'[]') from runspot_private.training_completions c where c.user_id=viewer)) from runspot_private.training_plans t where t.user_id=viewer);
end;
$$;
create function public.training_plan(operation text default 'read',kind text default null,start_day date default null,session_index integer default null,run_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.training_plan(operation,kind,start_day,session_index,run_id); $$;
revoke all on function public.training_plan(text,text,date,integer,uuid),runspot_private.training_plan(text,text,date,integer,uuid) from public,anon,authenticated;
grant execute on function public.training_plan(text,text,date,integer,uuid),runspot_private.training_plan(text,text,date,integer,uuid) to authenticated;

-- 크루원이 참여를 선택한 뒤 측정한 검증 완료 기록만 공동 목표에 합산합니다.
create table runspot_private.crew_challenges(
 id uuid primary key,crew_id uuid not null references runspot_private.crews(id) on delete cascade,
 target_km integer not null check(target_km between 1 and 10000),
 starts_at timestamptz not null default now(),ends_at timestamptz not null,
 check(ends_at>starts_at and ends_at<=starts_at+interval '90 days')
);
create table runspot_private.crew_challenge_members(
 challenge_id uuid references runspot_private.crew_challenges(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,joined_at timestamptz not null default now(),
 primary key(challenge_id,user_id)
);
alter table runspot_private.crew_challenges enable row level security;
alter table runspot_private.crew_challenge_members enable row level security;
revoke all on runspot_private.crew_challenges,runspot_private.crew_challenge_members from public,anon,authenticated;
create function runspot_private.crew_challenge(crew_id uuid,operation text default 'read',challenge_id uuid default null,target_km integer default null,days integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); owner boolean;
begin
 if not runspot_private.can_interact() then raise exception '로그인과 인증이 필요합니다.' using errcode='42501'; end if;
 select m.role='owner' into owner from runspot_private.crew_members m where m.crew_id=crew_challenge.crew_id and m.user_id=viewer for share;
 if not found then raise exception '크루원만 이용할 수 있습니다.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('challenge:'||crew_id::text,0));
 if operation='create' then
   if not owner then raise exception '크루장만 목표를 만들 수 있습니다.' using errcode='42501'; end if;
   if exists(select 1 from runspot_private.crew_challenges c where c.id=challenge_id and c.crew_id=crew_challenge.crew_id) then null;
   else
     if days is null or days not between 1 and 90 or target_km is null then raise exception '기간과 목표를 확인해 주세요.' using errcode='22023'; end if;
     if exists(select 1 from runspot_private.crew_challenges c where c.crew_id=crew_challenge.crew_id and c.ends_at>now()) then raise exception '진행 중인 공동 목표가 있습니다.' using errcode='22023'; end if;
     insert into runspot_private.crew_challenges(id,crew_id,target_km,ends_at) values(challenge_id,crew_id,target_km,now()+make_interval(days=>days));
   end if;
 elsif operation='join' then
   if not exists(select 1 from runspot_private.crew_challenges c where c.id=challenge_id and c.crew_id=crew_challenge.crew_id and c.ends_at>now()) then raise exception '참여할 목표가 없습니다.' using errcode='22023'; end if;
   insert into runspot_private.crew_challenge_members(challenge_id,user_id) values(challenge_id,viewer) on conflict do nothing;
 elsif operation='leave' then delete from runspot_private.crew_challenge_members m using runspot_private.crew_challenges c where m.challenge_id=c.id and c.id=crew_challenge.challenge_id and c.crew_id=crew_challenge.crew_id and m.user_id=viewer;
 elsif operation<>'read' or operation is null then raise exception '지원하지 않는 작업입니다.' using errcode='22023'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at desc),'[]') from (
   select c.*,exists(select 1 from runspot_private.crew_challenge_members cm where cm.challenge_id=c.id and cm.user_id=viewer) as joined,
   (select coalesce(sum(r.distance_m),0) from runspot_private.crew_challenge_members cm
     join runspot_private.crew_members m on m.user_id=cm.user_id and m.crew_id=c.crew_id
     join public.runs r on r.user_id=cm.user_id and r.started_at>=greatest(c.starts_at,cm.joined_at) and r.ended_at<=c.ends_at
     where cm.challenge_id=c.id and r.integrity_status='verified' and r.distance_m>=300 and not r.hidden) as distance_m
   from runspot_private.crew_challenges c where c.crew_id=crew_challenge.crew_id order by c.starts_at desc limit 12
 )x);
end;
$$;
create function public.crew_challenge(crew_id uuid,operation text default 'read',challenge_id uuid default null,target_km integer default null,days integer default null) returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.crew_challenge(crew_id,operation,challenge_id,target_km,days); $$;
revoke all on function public.crew_challenge(uuid,text,uuid,integer,integer),runspot_private.crew_challenge(uuid,text,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.crew_challenge(uuid,text,uuid,integer,integer),runspot_private.crew_challenge(uuid,text,uuid,integer,integer) to authenticated;
notify pgrst,'reload schema';
