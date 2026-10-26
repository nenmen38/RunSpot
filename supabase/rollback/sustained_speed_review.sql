-- 새 측정이 접수되었으면 자동 복구를 중단하고 데이터 보존 계획을 먼저 수립합니다.
begin;
lock table public.runs in access exclusive mode;
do $$ begin
 if exists(select 1 from public.runs where motion_evidence is not null)
   or exists(select 1 from runspot_private.run_motion_samples) then
  raise exception '새 위치 측정 기록이 있어 자동 복구를 중단합니다.';
 end if;
end; $$;
drop trigger runs_mark_review_pending on public.runs;
create or replace function runspot_private.mark_run_review_pending()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.review_pending := new.integrity_status='pending' and (
    (new.distance_m>0 and new.duration_sec=0)
    or (new.duration_sec>0 and new.distance_m::numeric/new.duration_sec>6.5)
    or runspot_private.has_suspicious_splits(new.split_data));
  return new;
end;
$$;
create or replace function runspot_private.open_integrity_case()
returns trigger language plpgsql security definer set search_path = '' as $$
declare rule text;
begin
  if runspot_private.has_suspicious_splits(new.split_data) then
    rule := 'split_speed_over_6_5';
  elsif (new.distance_m > 0 and new.duration_sec = 0)
    or (new.duration_sec > 0 and new.distance_m::numeric/new.duration_sec > 6.5) then
    rule := 'average_speed_over_6_5';
  end if;
  if rule is not null then
    insert into runspot_private.integrity_cases(run_id,rule_code,risk_score)
      values(new.id,rule,90) on conflict(run_id) do nothing;
  end if;
  return null;
end;
$$;
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
create or replace function runspot_private.review_cases()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if runspot_private.staff_role() is null then
    raise exception '관리자 권한과 다중 인증이 필요합니다.' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(entry order by created_at,id),'[]'::jsonb) from (
    select c.id,c.created_at,jsonb_build_object('id',c.id,'nickname',coalesce(p.nickname,'닉네임 없음'),
      'rule',c.rule_code,'risk',c.risk_score,'status',c.status,'distance_m',r.distance_m,
      'duration_sec',r.duration_sec,'splits',r.split_data) entry
    from runspot_private.integrity_cases c join public.runs r on r.id=c.run_id
    join public.profiles p on p.id=r.user_id where c.status in ('open','evidence_requested')
    order by c.created_at,c.id limit 100
  ) cases);
end;
$$;
create trigger runs_mark_review_pending before insert or update of integrity_status,distance_m,duration_sec,split_data
 on public.runs for each row execute function runspot_private.mark_run_review_pending();
drop function public.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb);
drop function runspot_private.save_my_run_with_motion(uuid,timestamptz,timestamptz,integer,integer,jsonb,double precision,timestamptz,jsonb,jsonb);
drop function runspot_private.evaluate_run_motion(jsonb,timestamptz,timestamptz);
drop function runspot_private.motion_distance(double precision,double precision,double precision,double precision);
drop table runspot_private.run_motion_samples;
alter table public.runs drop column motion_evidence;
notify pgrst,'reload schema';
commit;
