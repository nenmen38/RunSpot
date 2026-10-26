-- 판정은 서버가 결정하고 클라이언트는 보류 여부를 변경할 수 없습니다.
alter table public.runs add column review_pending boolean not null default false;
alter table runspot_private.run_rewards drop constraint run_rewards_reason_check;
alter table runspot_private.run_rewards add constraint run_rewards_reason_check
  check(reason in ('too_short','too_fast','late_sync','daily_limit','review_pending'));

create function runspot_private.mark_run_review_pending()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.review_pending := new.integrity_status='pending' and (
    (new.distance_m>0 and new.duration_sec=0)
    or (new.duration_sec>0 and new.distance_m::numeric/new.duration_sec>6.5)
    or runspot_private.has_suspicious_splits(new.split_data));
  return new;
end;
$$;
revoke all on function runspot_private.mark_run_review_pending() from public,anon,authenticated;
create trigger runs_mark_review_pending before insert or update of integrity_status,distance_m,duration_sec,split_data
  on public.runs for each row execute function runspot_private.mark_run_review_pending();

-- 일반 저장과 관리자 승인의 지급 계산을 같은 계정 잠금 안에서 수행합니다.
-- 내부 함수이며 로그인 사용자가 직접 호출할 수 없습니다.
create function runspot_private.settle_run_reward(requested_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  item public.runs;
  previous runspot_private.run_rewards;
  existing boolean;
  owner_total integer;
  day_total integer;
  earned integer := 0;
  why text;
  original_saved_at timestamptz;
begin
  select * into item from public.runs where id=requested_id;
  if not found then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('run_rewards:'||item.user_id::text,0));
  select * into previous from runspot_private.run_rewards where run_id=requested_id for update;
  existing := found;
  if existing and previous.reason is distinct from 'review_pending' then return; end if;
  if item.integrity_status='rejected' then return; end if;
  if existing and not item.review_pending and item.integrity_status<>'verified' then return; end if;
  select coalesce(sum(w.xp),0)::integer into owner_total
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
    where w.user_id=item.user_id and r.id<>item.id and not r.review_pending and r.integrity_status<>'rejected';
  if item.review_pending then
    insert into runspot_private.run_rewards(run_id,user_id,xp,reason,total_before,level_before,level_after)
      values(item.id,item.user_id,0,'review_pending',owner_total,
        runspot_private.level_for_xp(owner_total),runspot_private.level_for_xp(owner_total))
      on conflict(run_id) do nothing;
    return;
  end if;
  select coalesce(sum(w.xp),0)::integer into day_total
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
    where w.user_id=item.user_id and r.id<>item.id and not r.review_pending and r.integrity_status<>'rejected'
      and (r.ended_at at time zone 'Asia/Seoul')::date=(item.ended_at at time zone 'Asia/Seoul')::date;
  original_saved_at := case when existing then previous.awarded_at else now() end;
  if item.distance_m<300 then why := 'too_short';
  elsif item.duration_sec<=0 or (item.integrity_status<>'verified' and item.distance_m::numeric/item.duration_sec>6.5) then
    why := 'too_fast';
  elsif item.ended_at<original_saved_at-interval '7 days' then why := 'late_sync';
  else
    earned := least(300,10+item.distance_m/100);
    if day_total+earned>500 then earned := greatest(0,500-day_total); why := 'daily_limit'; end if;
  end if;
  insert into runspot_private.run_rewards(run_id,user_id,xp,reason,total_before,level_before,level_after)
    values(item.id,item.user_id,earned,why,owner_total,
      runspot_private.level_for_xp(owner_total),runspot_private.level_for_xp(owner_total+earned))
    on conflict(run_id) do update set xp=excluded.xp,reason=excluded.reason,total_before=excluded.total_before,
      level_before=excluded.level_before,level_after=excluded.level_after
    where runspot_private.run_rewards.reason='review_pending';
end;
$$;
revoke all on function runspot_private.settle_run_reward(uuid) from public,anon,authenticated;

create or replace function runspot_private.award_run_reward()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform runspot_private.settle_run_reward(new.id);
  return null;
end;
$$;

create or replace function runspot_private.my_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return runspot_private.progress_for_xp((select coalesce(sum(w.xp),0)::integer
    from runspot_private.run_rewards w join public.runs r on r.id=w.run_id
    where w.user_id=auth.uid() and not r.review_pending and r.integrity_status<>'rejected'));
end;
$$;

create or replace function runspot_private.my_run_reward(requested_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare reward runspot_private.run_rewards; rejected boolean; held boolean; progress jsonb;
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  select w.* into reward from runspot_private.run_rewards w where w.run_id=requested_run_id and w.user_id=auth.uid();
  if not found then return jsonb_build_object('status','unavailable','run_id',requested_run_id); end if;
  select integrity_status='rejected',review_pending into rejected,held from public.runs where id=requested_run_id;
  progress := runspot_private.my_progress();
  return jsonb_build_object('status','ready','run_id',requested_run_id,'xp',case when rejected or held then 0 else reward.xp end,
    'reason',case when rejected then 'rejected' when held then 'review_pending' else reward.reason end,
    'level_before',case when held then (progress->>'level')::integer else reward.level_before end,
    'level_after',case when held then (progress->>'level')::integer when rejected then reward.level_before else reward.level_after end,
    'progress',progress);
end;
$$;

create or replace function runspot_private.resolve_review(case_id uuid,decision text,note text)
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
  if decision='approved' then perform runspot_private.settle_run_reward(item.run_id); end if;
  update runspot_private.integrity_cases set status=decision,assigned_to=auth.uid() where id=case_id;
  insert into runspot_private.integrity_actions(case_id,actor_id,action,note) values(case_id,auth.uid(),decision,trim(note));
  insert into runspot_private.audit_logs(actor_id,action,target_id) values(auth.uid(),'integrity_'||decision,item.run_id);
end;
$$;

create or replace function runspot_private.refresh_achievements(owner_id uuid)
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
    from public.runs where user_id=owner_id and not review_pending and integrity_status<>'rejected'
      and distance_m>0 and duration_sec>0 and ended_at<=now()
  ) r on true
  where d.code in ('first_run','ten_runs','fifty_km') group by d.code,d.target,d.metric
  on conflict(user_id,achievement_code) do update set progress=excluded.progress,achieved_at=excluded.achieved_at;
end;
$$;

create or replace function runspot_private.friend_weekly_ranking()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := auth.uid();
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if viewer is null or not runspot_private.is_active(viewer) then
    raise exception '로그인과 계정 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if not runspot_private.can_interact() then
    return jsonb_build_object('can_interact', false, 'week_started_at', week_start, 'entries', '[]'::jsonb);
  end if;
  return (
    with participants as (
      select p.id, p.nickname from public.profiles p where p.id=viewer
      union all
      select p.id, p.nickname from public.friendships f
      join public.profiles p on p.id=case when f.user_low=viewer then f.user_high else f.user_low end
      where viewer in (f.user_low,f.user_high) and f.status='accepted'
        and p.nickname is not null and runspot_private.email_verified(p.id)
        and runspot_private.can_read(p.id,p.visibility)
    ), totals as (
      select p.id, p.nickname, coalesce(sum(r.distance_m),0) as distance_m
      from participants p left join public.runs r on r.user_id=p.id
        and r.ended_at >= week_start and r.ended_at < week_start + interval '7 days'
        and r.ended_at <= now() and not r.review_pending and r.integrity_status <> 'rejected'
      group by p.id,p.nickname
    ), ranked as (
      select rank() over(order by t.distance_m desc) as rank,
        t.id, t.nickname, t.distance_m, t.id=viewer as is_me from totals t
    )
    select jsonb_build_object('can_interact',true,'week_started_at',week_start,
      'entries',coalesce(jsonb_agg(jsonb_build_object(
        'rank',r.rank,'nickname',r.nickname,'distance_m',r.distance_m,'is_me',r.is_me
      ) order by r.distance_m desc,r.nickname,r.id),'[]'::jsonb)) from ranked r
  );
end;
$$;

create or replace function runspot_private.group_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not runspot_private.is_active(auth.uid()) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  return jsonb_build_object('server_now',clock_timestamp(),'groups',(
    select coalesce(jsonb_agg(entry order by created_at desc,id),'[]'::jsonb) from (
      select g.created_at,g.id,jsonb_build_object('id',g.id,'host_id',g.host_id,'starts_at',g.starts_at,
        'state',case when g.state in ('lobby','scheduled') and g.expires_at<=now() then 'expired'
          when g.state='scheduled' and g.starts_at<=now() then 'running' else g.state end,
        'my_status',mine.status,'members',(
          select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'nickname',coalesce(p.nickname,'닉네임 없음'),
            'status',m.status,'ready',m.ready_at>now()-interval '30 seconds','client_run_id',case when m.user_id=auth.uid() then m.client_run_id end,
            'distance_m',case when mine.status in ('accepted','finished') and m.status='finished' and not r.review_pending and r.integrity_status<>'rejected' then r.distance_m end,
            'duration_sec',case when mine.status in ('accepted','finished') and m.status='finished' and not r.review_pending and r.integrity_status<>'rejected' then r.duration_sec end)
            order by m.created_at,m.user_id),'[]'::jsonb)
          from runspot_private.running_group_members m join public.profiles p on p.id=m.user_id
          left join public.runs r on r.id=m.run_id
          where m.group_id=g.id and runspot_private.is_active(m.user_id)
            and (m.user_id=auth.uid() or m.user_id=g.host_id or g.host_id=auth.uid()
              or (mine.status in ('accepted','finished') and m.status in ('accepted','finished')))
            and not exists(select 1 from runspot_private.blocks b where
              (b.blocker_id=auth.uid() and b.blocked_id=m.user_id) or (b.blocked_id=auth.uid() and b.blocker_id=m.user_id))
        )) entry
      from runspot_private.running_groups g join runspot_private.running_group_members mine on mine.group_id=g.id and mine.user_id=auth.uid()
      where mine.status in ('invited','accepted','finished','left','cancelled') and runspot_private.group_allowed(g.id)
      order by g.created_at desc,g.id limit 20
    ) recent_groups));
end;
$$;

create or replace function runspot_private.save_my_run_with_splits(
  client_id uuid, start_time timestamptz, end_time timestamptz,
  distance_metres integer, active_seconds integer, route_segments jsonb,
  temperature_c double precision, temperature_observed_at timestamptz, split_data jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  saved public.runs;
  summary jsonb;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태와 계정 이용 권한을 확인해 주세요.' using errcode='42501';
  end if;
  if client_id is null or start_time is null or end_time is null
    or not isfinite(start_time) or not isfinite(end_time)
    or end_time <= start_time or end_time > now() + interval '5 minutes'
    or end_time - start_time > interval '7 days'
    or distance_metres is null or distance_metres < 0 or distance_metres > 1000000
    or active_seconds is null or active_seconds < 0
    or active_seconds > extract(epoch from end_time - start_time) + 1
    or not runspot_private.valid_run_splits(split_data,distance_metres,active_seconds) then
    raise exception '러닝 기록의 구간·거리·시간 또는 날짜가 올바르지 않습니다.' using errcode='22023';
  end if;
  -- 구간과 기온을 최초 삽입에 포함해 재전송 및 동시 요청의 값을 고정합니다.
  insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,
    temperature_c,temperature_observed_at,split_data)
  values(owner_id,client_id,start_time,end_time,distance_metres,active_seconds,
    temperature_c,temperature_observed_at,split_data)
  on conflict(user_id,client_run_id) do nothing;
  select * into strict saved from public.runs r
    where r.user_id=owner_id and r.client_run_id=client_id for update;
  if saved.split_data is distinct from split_data then
    raise exception '이미 저장된 구간 기록과 재시도 내용이 다릅니다.' using errcode='22023';
  end if;
  -- 기존 날짜·기온·경로 검사가 실패하면 구간 기록 삽입도 함께 취소됩니다.
  summary := runspot_private.save_my_run_with_temperature(client_id,start_time,end_time,
    distance_metres,active_seconds,route_segments,temperature_c,temperature_observed_at);
  return summary || jsonb_build_object('split_data',saved.split_data,'review_pending',saved.review_pending,'integrity_status',saved.integrity_status);
end;
$$;

-- 기존 미처리 의심 기록도 보류하며 이미 확정된 관리자 결정은 유지합니다.
insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
  select id,case when runspot_private.has_suspicious_splits(split_data) then 'split_speed_over_6_5'
    else 'average_speed_over_6_5' end,90 from public.runs
  where integrity_status='pending' and ((distance_m>0 and duration_sec=0)
    or (duration_sec>0 and distance_m::numeric/duration_sec>6.5)
    or runspot_private.has_suspicious_splits(split_data)) on conflict(run_id) do nothing;
update public.runs r set review_pending=true where r.integrity_status='pending'
  and exists(select 1 from runspot_private.integrity_cases c where c.run_id=r.id and c.status in ('open','evidence_requested'));
update runspot_private.run_rewards w set xp=0,reason='review_pending',level_after=level_before
  from public.runs r where r.id=w.run_id and r.review_pending;
-- 다음 조회뿐 아니라 기존 업적 캐시도 보류 상태에 맞춥니다.
do $$ declare owner_id uuid; begin
  for owner_id in select distinct user_id from public.runs where review_pending loop
    perform runspot_private.refresh_achievements(owner_id);
  end loop;
end; $$;
notify pgrst,'reload schema';
