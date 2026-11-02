-- 운영자가 계정별 대기 시간을 초기화해도 실제 호출 시각과 전체 예산 이력은 보존합니다.
create table runspot_private.feedback_cooldown_resets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reset_at timestamptz not null default clock_timestamp(),
  reason text not null check(char_length(btrim(reason)) between 1 and 500)
);
alter table runspot_private.feedback_cooldown_resets enable row level security;
revoke all on runspot_private.feedback_cooldown_resets from public,anon,authenticated;

create or replace function runspot_private.feedback_state(owner_id uuid, target_run uuid)
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
    where user_id=owner_id and (
      created_at >= coalesce((select reset_at from runspot_private.feedback_cooldown_resets
        where user_id=owner_id), '-infinity'::timestamptz)
      -- 초기화가 있어도 진행 중인 요청과 중복 실행하지 않습니다.
      or (state='pending' and created_at+interval '2 minutes'>now())
    ) order by created_at desc,id desc limit 1;
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

notify pgrst, 'reload schema';
