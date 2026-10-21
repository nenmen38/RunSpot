-- 업적은 서버 저장이 완료된 유효 이동 기록으로 계산합니다.
alter table public.achievement_definitions drop constraint achievement_definitions_metric_check;
alter table public.achievement_definitions add constraint achievement_definitions_metric_check
  check(metric in ('distinct_routes','night_runs','elevation_m','run_count','distance_m'));
insert into public.achievement_definitions(code,title,metric,target) values
 ('first_run','첫 러닝 완료','run_count',1),('ten_runs','누적 10회','run_count',10),
 ('fifty_km','누적 50km','distance_m',50000);

create function runspot_private.refresh_achievements(owner_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- 회원 삭제의 연쇄 기록 삭제에서는 이미 사라진 계정의 업적을 다시 만들지 않습니다.
  if not exists(select 1 from auth.users where id=owner_id) then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:'||owner_id::text,0));
  insert into public.user_achievements(user_id,achievement_code,progress,achieved_at)
  select owner_id,d.code,least(d.target,coalesce(max(case when d.metric='run_count' then r.run_count else r.distance end),0))::integer,
    min(r.ended_at) filter(where case when d.metric='run_count' then r.run_count else r.distance end >= d.target)
  from public.achievement_definitions d left join (
    select ended_at,
      count(*) over(order by ended_at,id rows unbounded preceding) run_count,
      sum(distance_m::bigint) over(order by ended_at,id rows unbounded preceding) distance
    from public.runs where user_id=owner_id and integrity_status<>'rejected'
      and distance_m>0 and duration_sec>0 and ended_at<=now()
  ) r on true
  where d.code in ('first_run','ten_runs','fifty_km') group by d.code,d.target,d.metric
  on conflict(user_id,achievement_code) do update set progress=excluded.progress,achieved_at=excluded.achieved_at;
end;
$$;
revoke all on function runspot_private.refresh_achievements(uuid) from public,anon,authenticated;

create function runspot_private.runs_refresh_achievements()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform runspot_private.refresh_achievements(case when tg_op='DELETE' then old.user_id else new.user_id end);
  return null;
end;
$$;
revoke all on function runspot_private.runs_refresh_achievements() from public,anon,authenticated;
create trigger runs_refresh_achievements after insert or update of integrity_status or delete on public.runs
  for each row execute function runspot_private.runs_refresh_achievements();

create function runspot_private.my_achievements()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 기존 기록과 미래 종료 시각이 지난 기록도 최초 조회에서 반영합니다.
  perform runspot_private.refresh_achievements(auth.uid());
  return (select coalesce(jsonb_agg(jsonb_build_object('code',d.code,'title',d.title,
    'metric',d.metric,'target',d.target,'progress',a.progress,'achieved_at',a.achieved_at) order by d.target,d.code),'[]'::jsonb)
    from public.user_achievements a join public.achievement_definitions d on d.code=a.achievement_code
    where a.user_id=auth.uid() and d.code in ('first_run','ten_runs','fifty_km'));
end;
$$;
create function public.my_achievements() returns jsonb language sql security invoker set search_path = ''
as $$ select runspot_private.my_achievements(); $$;
revoke all on function runspot_private.my_achievements(),public.my_achievements() from public,anon,authenticated;
grant execute on function runspot_private.my_achievements(),public.my_achievements() to authenticated;

-- 평균 이동 속도 6.5m/s 초과 기록만 자동 검토 대상으로 만듭니다. GPS 원본은 공개하지 않습니다.
create function runspot_private.open_integrity_case()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.duration_sec>0 and new.distance_m::numeric/new.duration_sec>6.5 then
    insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
      values(new.id,'average_speed_over_6_5',90) on conflict(run_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function runspot_private.open_integrity_case() from public,anon,authenticated;
create trigger runs_integrity_case after insert on public.runs for each row execute function runspot_private.open_integrity_case();
insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
  select id,'average_speed_over_6_5',90 from public.runs where duration_sec>0
  and distance_m::numeric/duration_sec>6.5 and integrity_status='pending' on conflict(run_id) do nothing;

create function runspot_private.review_cases()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if runspot_private.staff_role() is null then
    raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(entry order by created_at,id),'[]'::jsonb) from (
    select c.id,c.created_at,jsonb_build_object('id',c.id,'nickname',coalesce(p.nickname,'닉네임 없음'),
      'rule',c.rule_code,'risk',c.risk_score,'status',c.status,'distance_m',r.distance_m,
      'duration_sec',r.duration_sec) entry
    from runspot_private.integrity_cases c join public.runs r on r.id=c.run_id
    join public.profiles p on p.id=r.user_id where c.status in ('open','evidence_requested')
    order by c.created_at,c.id limit 100
  ) cases);
end;
$$;

create function runspot_private.resolve_review(case_id uuid,decision text,note text)
returns void language plpgsql security definer set search_path = '' as $$
declare item runspot_private.integrity_cases; owner_id uuid;
begin
  -- 역할 회수와 조치를 직렬화하고 JWT 메타데이터로 권한을 부여하지 않습니다.
  perform 1 from runspot_private.user_roles where user_id=auth.uid() for share;
  perform 1 from runspot_private.account_controls where user_id=auth.uid() for share;
  if runspot_private.staff_role() is null then
    raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  if decision is null or decision not in ('approved','rejected') or note is null or length(trim(note)) not between 1 and 2000 then
    raise exception '처리 사유를 1~2000자로 입력해 주세요.' using errcode='22023';
  end if;
  select * into item from runspot_private.integrity_cases where id=case_id for update;
  if not found then raise exception '검토 건을 찾을 수 없습니다.' using errcode='22023'; end if;
  select user_id into owner_id from public.runs where id=item.run_id;
  if owner_id=auth.uid() then raise exception '본인 기록은 검토할 수 없습니다.' using errcode='42501'; end if;
  if item.status=decision then return; end if;
  if item.status not in ('open','evidence_requested') then
    raise exception '이미 처리한 검토 건입니다. 새로고침해 주세요.' using errcode='P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:'||owner_id::text,0));
  update public.runs set integrity_status=case when decision='approved' then 'verified' else 'rejected' end where id=item.run_id;
  update runspot_private.integrity_cases set status=decision,assigned_to=auth.uid() where id=case_id;
  insert into runspot_private.integrity_actions(case_id,actor_id,action,note) values(case_id,auth.uid(),decision,trim(note));
  insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'integrity_'||decision,item.run_id);
end;
$$;
create function public.review_cases() returns jsonb language sql stable security invoker set search_path = ''
as $$ select runspot_private.review_cases(); $$;
create function public.resolve_review(case_id uuid,decision text,note text) returns void language sql security invoker set search_path = ''
as $$ select runspot_private.resolve_review(case_id,decision,note); $$;
revoke all on function runspot_private.review_cases(),runspot_private.resolve_review(uuid,text,text),public.review_cases(),public.resolve_review(uuid,text,text) from public,anon,authenticated;
grant execute on function runspot_private.review_cases(),runspot_private.resolve_review(uuid,text,text),public.review_cases(),public.resolve_review(uuid,text,text) to authenticated;

-- 지급 이력을 보존하되 반려 기록의 보상은 현재 잔액과 조회 결과에서 제외합니다.
create or replace function runspot_private.my_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return runspot_private.progress_for_xp((select coalesce(sum(w.xp),0)::integer
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
    where w.user_id=auth.uid() and r.integrity_status<>'rejected'));
end;
$$;
create or replace function runspot_private.my_run_reward(requested_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare reward runspot_private.run_rewards; rejected boolean;
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  select w.* into reward from runspot_private.run_rewards w where w.run_id=requested_run_id and w.user_id=auth.uid();
  if not found then return jsonb_build_object('status','unavailable','run_id',requested_run_id); end if;
  select integrity_status='rejected' into rejected from public.runs where id=requested_run_id;
  return jsonb_build_object('status','ready','run_id',requested_run_id,'xp',case when rejected then 0 else reward.xp end,
    'reason',case when rejected then 'rejected' else reward.reason end,
    'level_before',reward.level_before,'level_after',case when rejected then reward.level_before else reward.level_after end,
    'progress',runspot_private.my_progress());
end;
$$;
create or replace function runspot_private.award_run_reward()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner_total integer;
  day_total integer;
  earned integer;
  why text;
begin
  -- 같은 계정의 동시 저장이 일일 한도와 레벨 계산을 함께 넘지 않도록 직렬화합니다.
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:' || new.user_id::text, 0));
  select coalesce(sum(xp), 0) into owner_total
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id where w.user_id = new.user_id and r.integrity_status<>'rejected';
  select coalesce(sum(w.xp), 0) into day_total
    from runspot_private.run_rewards w join public.runs r on r.id = w.run_id
    where w.user_id = new.user_id and r.integrity_status<>'rejected'
      and (r.ended_at at time zone 'Asia/Seoul')::date = (new.ended_at at time zone 'Asia/Seoul')::date;

  -- 기기 측정값이므로 짧은 기록·비현실적 속도·오래된 기록은 저장만 하고 보상하지 않습니다.
  if new.distance_m < 300 then
    earned := 0; why := 'too_short';
  elsif new.duration_sec <= 0 or new.distance_m::numeric / new.duration_sec > 6.5 then
    earned := 0; why := 'too_fast';
  elsif new.ended_at < now() - interval '7 days' then
    earned := 0; why := 'late_sync';
  else
    earned := least(300, 10 + new.distance_m / 100);
    if day_total + earned > 500 then
      earned := greatest(0, 500 - day_total); why := 'daily_limit';
    end if;
  end if;

  insert into runspot_private.run_rewards(run_id,user_id,xp,reason,total_before,level_before,level_after)
  values(new.id,new.user_id,earned,why,owner_total,
    runspot_private.level_for_xp(owner_total),runspot_private.level_for_xp(owner_total + earned));
  return null;
end;
$$;
notify pgrst,'reload schema';
