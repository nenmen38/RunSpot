-- 원시 위치는 비공개로 보관하고 공개 기록에는 서버가 계산한 의심 구간만 저장합니다.
alter table public.runs add column motion_evidence jsonb;
create table runspot_private.run_motion_samples (
  run_id uuid primary key references public.runs(id) on delete cascade,
  samples jsonb not null
);
alter table runspot_private.run_motion_samples enable row level security;
create policy motion_samples_service_access on runspot_private.run_motion_samples
  for all to service_role using (true) with check (true);
revoke all on runspot_private.run_motion_samples from public,anon,authenticated;
grant select,insert,update,delete on runspot_private.run_motion_samples to service_role;

create function runspot_private.motion_distance(a double precision,b double precision,c double precision,d double precision)
returns double precision language sql immutable set search_path='' as $$
  select 12742000 * asin(sqrt(least(1.0,greatest(0.0,
    power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2)))));
$$;
revoke all on function runspot_private.motion_distance(double precision,double precision,double precision,double precision) from public,anon,authenticated;

-- 매 표본에서 직전 60초를 확인해 고속 이동 시작 시점이 30초 경계와 달라도 찾습니다.
create function runspot_private.evaluate_run_motion(data jsonb,start_time timestamptz,end_time timestamptz)
returns jsonb language plpgsql immutable set search_path='' as $$
declare
  item jsonb; v double precision[]; prev double precision[]; lower_point double precision[];
  upper_point double precision[]; first_point double precision[]; middle_point double precision[];
  boundary double precision[]; history jsonb:='[]'; evidence jsonb:='[]';
  last_time double precision := -1; last_segment double precision := -1;
  ratio double precision; speed1 double precision; speed2 double precision; target double precision; gap double precision;
begin
  if data is null or jsonb_typeof(data)<>'array' then
    raise exception '위치 측정값이 올바르지 않습니다.' using errcode='22023';
  end if;
  if jsonb_array_length(data)>250000 or octet_length(data::text)>33554432 then
    raise exception '위치 측정값이 너무 큽니다.' using errcode='22023';
  end if;
  for item in select value from jsonb_array_elements(data) loop
    if jsonb_typeof(item)<>'array' or jsonb_array_length(item)<>5 then
      raise exception '위치 측정 형식이 올바르지 않습니다.' using errcode='22023';
    end if;
    if exists(select 1 from jsonb_array_elements(item) x where jsonb_typeof(x)<>'number') then
      raise exception '위치 측정 형식이 올바르지 않습니다.' using errcode='22023';
    end if;
    v := array[(item->>0)::double precision,(item->>1)::double precision,(item->>2)::double precision,
      (item->>3)::double precision,(item->>4)::double precision];
    if v[1]<>trunc(v[1]) or v[1]<=last_time
      or v[1]<trunc(extract(epoch from start_time)*1000) or v[1]>extract(epoch from end_time)*1000+1000
      or v[2] not between -90 and 90 or v[3] not between -180 and 180
      or v[4] not between 0 and 100 or v[5]<greatest(0,last_segment) or v[5]<>trunc(v[5]) then
      raise exception '위치 측정 시각과 범위가 올바르지 않습니다.' using errcode='22023';
    end if;
    last_time:=v[1]; last_segment:=v[5];
    if v[4]>25 then prev:=null; history:='[]'; continue; end if;
    if prev is not null then
      gap:=(v[1]-prev[1])/1000;
      if v[5]<>prev[5] or gap>10 or
        runspot_private.motion_distance(prev[2],prev[3],v[2],v[3])-prev[4]-v[4]>35*gap then
        history:='[]';
      elsif gap<1 then
        -- 과도하게 촘촘한 입력도 원본은 검증하되 판정 메모리는 1초 간격으로 제한합니다.
        continue;
      end if;
    end if;
    history:=history||jsonb_build_array(to_jsonb(v));
    while jsonb_array_length(history)>2 and (history->1->>0)::double precision<=v[1]-60000 loop
      history:=history-0;
    end loop;
    prev:=v;
    if evidence<>'[]'::jsonb or (history->0->>0)::double precision>v[1]-60000 then continue; end if;
    foreach target in array array[v[1]-60000,v[1]-30000] loop
      lower_point:=null; boundary:=null;
      for item in select value from jsonb_array_elements(history) loop
        upper_point:=array[(item->>0)::double precision,(item->>1)::double precision,(item->>2)::double precision,
          (item->>3)::double precision,(item->>4)::double precision];
        if upper_point[1]=target then boundary:=upper_point; exit;
        elsif upper_point[1]>target then
          ratio:=(target-lower_point[1])/(upper_point[1]-lower_point[1]);
          -- 날짜 변경선을 지나도 짧은 방향으로 보간합니다.
          boundary:=array[target,lower_point[2]+(upper_point[2]-lower_point[2])*ratio,
            lower_point[3]+(upper_point[3]-lower_point[3]-360*floor((upper_point[3]-lower_point[3]+180)/360))*ratio,
            greatest(lower_point[4],upper_point[4]),v[5]];
          boundary[3]:=boundary[3]-360*floor((boundary[3]+180)/360);
          exit;
        end if;
        lower_point:=upper_point;
      end loop;
      if target=v[1]-60000 then first_point:=boundary; else middle_point:=boundary; end if;
    end loop;
    -- 정확도 반경을 빼므로 순간 좌표 흔들림으로 속도가 부풀려지지 않습니다.
    speed1:=greatest(0,runspot_private.motion_distance(first_point[2],first_point[3],middle_point[2],middle_point[3])-first_point[4]-middle_point[4])/30;
    speed2:=greatest(0,runspot_private.motion_distance(middle_point[2],middle_point[3],v[2],v[3])-middle_point[4]-v[4])/30;
    if speed1>6.500001 and speed2>6.500001 then
      -- 최초 연속 60초만 근거로 남겨 긴 러닝에서도 응답 크기를 제한합니다.
      evidence:=jsonb_build_array(
        jsonb_build_object('start_s',greatest(0,(first_point[1]-extract(epoch from start_time)*1000)/1000),
          'end_s',greatest(0,(middle_point[1]-extract(epoch from start_time)*1000)/1000),
          'speed_kmh',round((speed1*3.6)::numeric,2),'accuracy_m',greatest(first_point[4],middle_point[4])),
        jsonb_build_object('start_s',greatest(0,(middle_point[1]-extract(epoch from start_time)*1000)/1000),
          'end_s',greatest(0,(v[1]-extract(epoch from start_time)*1000)/1000),
          'speed_kmh',round((speed2*3.6)::numeric,2),'accuracy_m',greatest(middle_point[4],v[4])));
    end if;
  end loop;
  return evidence;
end;
$$;
revoke all on function runspot_private.evaluate_run_motion(jsonb,timestamptz,timestamptz) from public,anon,authenticated;

create or replace function runspot_private.mark_run_review_pending()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.review_pending:=new.integrity_status='pending' and case when new.motion_evidence is not null
    then jsonb_array_length(new.motion_evidence)>0 else
      (new.distance_m>0 and new.duration_sec=0)
      or (new.duration_sec>0 and new.distance_m::numeric/new.duration_sec>6.5)
      or runspot_private.has_suspicious_splits(new.split_data) end;
  return new;
end;
$$;
drop trigger runs_mark_review_pending on public.runs;
create trigger runs_mark_review_pending before insert or update of integrity_status,distance_m,duration_sec,split_data,motion_evidence
  on public.runs for each row execute function runspot_private.mark_run_review_pending();

create or replace function runspot_private.open_integrity_case()
returns trigger language plpgsql security definer set search_path='' as $$
declare rule text;
begin
  if new.motion_evidence is not null then
    if jsonb_array_length(new.motion_evidence)>0 then rule:='sustained_speed_over_6_5'; end if;
  elsif runspot_private.has_suspicious_splits(new.split_data) then rule:='split_speed_over_6_5';
  elsif (new.distance_m>0 and new.duration_sec=0)
    or (new.duration_sec>0 and new.distance_m::numeric/new.duration_sec>6.5) then rule:='average_speed_over_6_5';
  end if;
  if rule is not null then
    insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
      values(new.id,rule,90) on conflict(run_id) do nothing;
  end if;
  return null;
end;
$$;

create function runspot_private.save_my_run_with_motion(
  client_id uuid,start_time timestamptz,end_time timestamptz,distance_metres integer,active_seconds integer,
  route_segments jsonb,temperature_c double precision,temperature_observed_at timestamptz,split_data jsonb,motion_samples jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); result jsonb; saved public.runs; evidence jsonb; existing jsonb;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  if start_time is null or end_time is null or not isfinite(start_time) or not isfinite(end_time)
    or end_time<=start_time or end_time-start_time>interval '7 days' or end_time>now()+interval '5 minutes' then
    raise exception '측정 시간이 올바르지 않습니다.' using errcode='22023';
  end if;
  evidence:=runspot_private.evaluate_run_motion(motion_samples,start_time,end_time);
  -- 보상·업적 트리거보다 먼저 판정 근거를 삽입해 보류 없이 지급되는 순간을 없앱니다.
  insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,
    temperature_c,temperature_observed_at,split_data,motion_evidence)
    values(owner_id,client_id,start_time,end_time,distance_metres,active_seconds,
      temperature_c,temperature_observed_at,split_data,evidence)
    on conflict(user_id,client_run_id) do nothing;
  select * into strict saved from public.runs where user_id=owner_id and client_run_id=client_id for update;
  if saved.motion_evidence is distinct from evidence then
    raise exception '이미 저장된 위치 검증 결과와 다릅니다.' using errcode='22023';
  end if;
  insert into runspot_private.run_motion_samples(run_id,samples) values(saved.id,motion_samples) on conflict do nothing;
  select samples into strict existing from runspot_private.run_motion_samples where run_id=saved.id;
  if existing is distinct from motion_samples then
    raise exception '이미 저장된 위치 측정값과 다릅니다.' using errcode='22023';
  end if;
  result:=runspot_private.save_my_run_with_splits(client_id,start_time,end_time,distance_metres,active_seconds,
    route_segments,temperature_c,temperature_observed_at,split_data);
  return result||jsonb_build_object('motion_evidence',evidence);
end;
$$;
create function public.save_my_run_with_motion(
  client_id uuid,start_time timestamptz,end_time timestamptz,distance_metres integer,active_seconds integer,
  route_segments jsonb,temperature_c double precision,temperature_observed_at timestamptz,split_data jsonb,motion_samples jsonb
)
returns jsonb language sql security invoker set search_path='' as $$
  select runspot_private.save_my_run_with_motion(client_id,start_time,end_time,distance_metres,active_seconds,
    route_segments,temperature_c,temperature_observed_at,split_data,motion_samples);
$$;
revoke all on function public.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb),
  runspot_private.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb),
  runspot_private.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb) to authenticated;

create or replace function runspot_private.settle_run_reward(requested_id uuid)
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
  elsif item.duration_sec<=0 or (item.motion_evidence is null and item.integrity_status<>'verified' and item.distance_m::numeric/item.duration_sec>6.5) then
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

create or replace function runspot_private.review_cases()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if runspot_private.staff_role() is null then
    raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(entry order by created_at,id),'[]'::jsonb) from (
    select c.id,c.created_at,jsonb_build_object('id',c.id,'nickname',coalesce(p.nickname,'닉네임 없음'),
      'rule',c.rule_code,'risk',c.risk_score,'status',c.status,'distance_m',r.distance_m,
      'duration_sec',r.duration_sec,'splits',r.split_data,'motion_evidence',r.motion_evidence) entry
    from runspot_private.integrity_cases c join public.runs r on r.id=c.run_id
    join public.profiles p on p.id=r.user_id where c.status in ('open','evidence_requested')
    order by c.created_at,c.id limit 100
  ) cases);
end;
$$;


-- 기존 기록과 관리자 결정은 변경하지 않습니다.
notify pgrst,'reload schema';
