-- AI 요청 이력은 기록 삭제 후에도 남겨 72시간 제한과 호출 예산을 유지합니다.
create table runspot_private.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  run_id uuid references public.runs(id) on delete set null,
  state text not null default 'pending' check (state in ('pending','succeeded','failed')),
  created_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz
);
create index feedback_requests_owner_time on runspot_private.feedback_requests(user_id,created_at desc);
create index feedback_requests_time on runspot_private.feedback_requests(created_at);
create table runspot_private.feedback_limits (
  id boolean primary key default true check (id),
  daily_calls integer not null check (daily_calls between 0 and 10000),
  monthly_calls integer not null check (monthly_calls between 0 and 100000)
);
insert into runspot_private.feedback_limits values(true,100,1000);
alter table runspot_private.feedback_requests enable row level security;
alter table runspot_private.feedback_limits enable row level security;
revoke all on runspot_private.feedback_requests,runspot_private.feedback_limits from public,anon,authenticated;

create function runspot_private.feedback_state(owner_id uuid, target_run uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  saved public.run_feedback;
  latest runspot_private.feedback_requests;
begin
  if owner_id is null or not runspot_private.is_active(owner_id)
    or not exists(select 1 from public.runs where id=target_run and user_id=owner_id) then
    raise exception '본인 기록만 조회할 수 있습니다.' using errcode='42501';
  end if;
  select * into latest from runspot_private.feedback_requests
    where user_id=owner_id order by created_at desc,id desc limit 1;
  select * into saved from public.run_feedback where run_id=target_run and source='ai';
  if found then
    return jsonb_build_object('status','ready','message',saved.message,'created_at',saved.created_at,
      'next_available_at',latest.created_at+interval '72 hours');
  end if;
  if not runspot_private.email_verified(owner_id) then
    return jsonb_build_object('status','email_required');
  end if;
  if latest.created_at+interval '72 hours' > now() then
    return jsonb_build_object('status',case when latest.state='pending' and latest.run_id=target_run
      and latest.created_at+interval '2 minutes'>now() then 'processing' else 'cooldown' end,
      'next_available_at',latest.created_at+interval '72 hours');
  end if;
  if exists(select 1 from public.runs where id=target_run and
    (distance_m<100 or duration_sec<60 or ended_at>now())) then
    return jsonb_build_object('status','insufficient_data');
  end if;
  return jsonb_build_object('status','available');
end;
$$;

create function runspot_private.my_run_feedback(requested_run_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select runspot_private.feedback_state(auth.uid(),requested_run_id);
$$;
create function public.my_run_feedback(requested_run_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.my_run_feedback(requested_run_id);
$$;

-- 호출자 식별자는 검증된 Auth 사용자에서만 가져오며 예약은 서버 역할 전용입니다.
create function runspot_private.reserve_run_feedback(owner_id uuid, target_run uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  state jsonb;
  limits runspot_private.feedback_limits;
  request_id uuid;
  request_time timestamptz;
  sample_count integer;
  sample_distance bigint;
  sample_seconds bigint;
  current_run public.runs;
begin
  -- 계정 행 잠금으로 서로 다른 기록과 여러 기기의 동시 요청도 직렬화합니다.
  perform 1 from auth.users where id=owner_id for update;
  state := runspot_private.feedback_state(owner_id,target_run);
  if state->>'status'<>'available' then return state; end if;
  select * into strict limits from runspot_private.feedback_limits where id for update;
  request_time := clock_timestamp();
  if (select count(*) from runspot_private.feedback_requests
    where created_at>request_time-interval '24 hours')>=limits.daily_calls
    or (select count(*) from runspot_private.feedback_requests
    where created_at>request_time-interval '30 days')>=limits.monthly_calls then
    return jsonb_build_object('status','budget_exhausted');
  end if;
  select * into strict current_run from public.runs where id=target_run and user_id=owner_id;
  select count(*),coalesce(sum(distance_m),0),coalesce(sum(duration_sec),0)
    into sample_count,sample_distance,sample_seconds
    from (select distance_m,duration_sec from public.runs
      where user_id=owner_id and id<>target_run and ended_at<=current_run.started_at
      and started_at>=current_run.started_at-interval '30 days'
      and distance_m>=100 and duration_sec>=60
      order by started_at desc,id desc limit 5) samples;
  insert into runspot_private.feedback_requests(user_id,run_id,created_at)
    values(owner_id,target_run,request_time) returning id into request_id;
  return jsonb_build_object('status','reserved','request_id',request_id,
    'next_available_at',request_time+interval '72 hours',
    'summary',jsonb_build_object('current',jsonb_build_object(
      'distance_m',current_run.distance_m,'duration_sec',current_run.duration_sec,
      'pace_seconds_per_km',round(current_run.duration_sec*1000.0/current_run.distance_m)),
      'previous',jsonb_build_object('count',sample_count,'total_distance_m',sample_distance,
      'total_duration_sec',sample_seconds,'average_distance_m',case when sample_count>0 then round(sample_distance*1.0/sample_count) end,
      'pace_seconds_per_km',case when sample_distance>0 then round(sample_seconds*1000.0/sample_distance) end)));
end;
$$;
create function public.reserve_run_feedback(owner_id uuid, target_run uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.reserve_run_feedback(owner_id,target_run);
$$;

create function runspot_private.finish_run_feedback(
  request_id uuid, feedback_message text, input_count integer, output_count integer
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  request runspot_private.feedback_requests;
begin
  select * into strict request from runspot_private.feedback_requests where id=request_id for update;
  if request.state<>'pending' then return; end if;
  if input_count is null or output_count is null or input_count<0 or output_count<0
    or input_count>1000000 or output_count>1000000 then
    raise exception '사용량이 올바르지 않습니다.' using errcode='22023';
  end if;
  -- 호출 실패와 만료도 예산에서 환불하지 않습니다. 재전송은 새 AI 호출 없이 결과만 조회합니다.
  insert into runspot_private.ai_usage(request_id,user_id,feature,model,input_tokens,output_tokens)
    values(request.id,request.user_id,'run_feedback','gemini-3.5-flash-lite',input_count,output_count)
    on conflict do nothing;
  if feedback_message is not null and char_length(btrim(feedback_message)) between 1 and 500
    and request.created_at+interval '2 minutes'>clock_timestamp()
    and runspot_private.is_active(request.user_id)
    and exists(select 1 from public.runs where id=request.run_id and user_id=request.user_id) then
    insert into public.run_feedback(run_id,message,source,version)
      values(request.run_id,btrim(feedback_message),'ai','gemini-3.5-flash-lite-v1')
      on conflict(run_id) do update set message=excluded.message,source=excluded.source,
        version=excluded.version,created_at=excluded.created_at where public.run_feedback.source='rules';
    update runspot_private.feedback_requests set state='succeeded',finished_at=clock_timestamp() where id=request.id;
  else
    update runspot_private.feedback_requests set state='failed',finished_at=clock_timestamp() where id=request.id;
  end if;
end;
$$;
create function public.finish_run_feedback(request_id uuid, feedback_message text, input_count integer, output_count integer)
returns void language sql security invoker set search_path = '' as $$
  select runspot_private.finish_run_feedback(request_id,feedback_message,input_count,output_count);
$$;

revoke all on function runspot_private.feedback_state(uuid,uuid) from public,anon,authenticated;
revoke all on function runspot_private.my_run_feedback(uuid),public.my_run_feedback(uuid) from public,anon,authenticated;
grant execute on function runspot_private.my_run_feedback(uuid),public.my_run_feedback(uuid) to authenticated;
revoke all on function runspot_private.reserve_run_feedback(uuid,uuid),public.reserve_run_feedback(uuid,uuid),
  runspot_private.finish_run_feedback(uuid,text,integer,integer),public.finish_run_feedback(uuid,text,integer,integer)
  from public,anon,authenticated;
grant execute on function runspot_private.reserve_run_feedback(uuid,uuid),public.reserve_run_feedback(uuid,uuid),
  runspot_private.finish_run_feedback(uuid,text,integer,integer) to service_role;
notify pgrst,'reload schema';
