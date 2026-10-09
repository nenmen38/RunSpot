-- 발표 자료와 마지막 정상 자료를 함께 보관하며 사용자 위치는 저장하지 않습니다.
create table runspot_private.environment_shared_cache (
  cache_key text primary key check (length(cache_key) between 1 and 180),
  slot text not null,
  payload jsonb,
  updated_at timestamptz,
  fresh_until timestamptz not null default '-infinity',
  lease_token uuid,
  lease_until timestamptz not null default '-infinity',
  retry_after timestamptz not null default '-infinity',
  last_error text
);
create table runspot_private.environment_budgets (
  provider text primary key check (provider in ('kma','air','stations')),
  max_requests integer not null check (max_requests between 1 and 450)
);
insert into runspot_private.environment_budgets values ('kma',450),('air',450),('stations',450);
create table runspot_private.environment_attempts (
  id bigint generated always as identity primary key,
  provider text not null references runspot_private.environment_budgets(provider),
  reserved_at timestamptz not null default clock_timestamp()
);
create index environment_attempts_provider_time on runspot_private.environment_attempts(provider,reserved_at);
alter table runspot_private.environment_shared_cache enable row level security;
alter table runspot_private.environment_budgets enable row level security;
alter table runspot_private.environment_attempts enable row level security;
revoke all on runspot_private.environment_shared_cache,runspot_private.environment_budgets,
  runspot_private.environment_attempts from public,anon,authenticated,service_role;

create function runspot_private.claim_environment_refresh(requested_key text, requested_slot text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item runspot_private.environment_shared_cache; moment timestamptz; token uuid; state text;
begin
  if requested_key is null or length(requested_key) not between 1 and 180
    or requested_slot is null or length(requested_slot) not between 1 and 40 then
    raise exception '공동 갱신 요청이 올바르지 않습니다.' using errcode='22023';
  end if;
  insert into runspot_private.environment_shared_cache(cache_key,slot)
    values(requested_key,requested_slot) on conflict do nothing;
  select * into item from runspot_private.environment_shared_cache where cache_key=requested_key for update;
  moment := clock_timestamp();
  if item.slot=requested_slot and item.payload is not null and item.fresh_until>moment then
    state := 'fresh';
  elsif item.lease_until>moment then
    state := 'busy';
  elsif item.retry_after>moment then
    state := 'cooldown';
  else
    state := 'owner'; token := gen_random_uuid();
    update runspot_private.environment_shared_cache set lease_token=token,
      lease_until=moment+interval '180 seconds',slot=requested_slot,fresh_until='-infinity' where cache_key=requested_key;
  end if;
  return jsonb_build_object('state',state,'token',token,'payload',item.payload,
    'updatedAt',item.updated_at,'error',item.last_error);
end;
$$;

create function runspot_private.reserve_environment_attempt(requested_provider text, requested_key text, token uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare ceiling integer; used integer; moment timestamptz;
begin
  -- 동시 예약의 상한 판정과 기록을 같은 트랜잭션에 고정합니다.
  select max_requests into ceiling from runspot_private.environment_budgets where provider=requested_provider for update;
  if ceiling is null then raise exception '조회 기관이 올바르지 않습니다.' using errcode='22023'; end if;
  perform 1 from runspot_private.environment_shared_cache where cache_key=requested_key
    and lease_token=token and lease_until>clock_timestamp() for update;
  if not found then return 'refresh_superseded'; end if;
  moment := clock_timestamp();
  delete from runspot_private.environment_attempts where provider=requested_provider and reserved_at<=moment-interval '24 hours';
  select count(*) into used from runspot_private.environment_attempts where provider=requested_provider;
  if used>=ceiling then return 'quota_exhausted'; end if;
  -- 실패·시간 초과·페이지 요청도 각각 예약하며 예산을 돌려주지 않습니다.
  insert into runspot_private.environment_attempts(provider,reserved_at) values(requested_provider,moment);
  return 'allowed';
end;
$$;

create function runspot_private.complete_environment_refresh(
  requested_key text, token uuid, cache_payload jsonb, ttl_seconds integer, error_code text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare accepted text; moment timestamptz := clock_timestamp();
begin
  if ttl_seconds is null or ttl_seconds not between 1 and 86400
    or (error_code is null and (cache_payload is null or pg_column_size(cache_payload)>2000000))
    or (error_code is not null and error_code not in ('quota_exhausted','provider_unavailable',
      'permission_denied','no_data','invalid_response','not_configured','refresh_superseded')) then
    raise exception '공동 갱신 결과가 올바르지 않습니다.' using errcode='22023';
  end if;
  update runspot_private.environment_shared_cache set
    payload=case when error_code is null then cache_payload else payload end,
    updated_at=case when error_code is null then moment else updated_at end,
    fresh_until=case when error_code is null then moment+make_interval(secs=>ttl_seconds) else '-infinity' end,
    retry_after=case when error_code is null then '-infinity' else moment+interval '5 minutes' end,
    last_error=error_code,lease_token=null,lease_until='-infinity'
  where cache_key=requested_key and lease_token=token and lease_until>moment returning cache_key into accepted;
  -- 갱신 중인 행은 유지하고 일주일 이상 갱신되지 않은 다른 지역 자료를 정리합니다.
  delete from runspot_private.environment_shared_cache where cache_key<>requested_key
    and lease_until<=moment and coalesce(updated_at,retry_after)<moment-interval '7 days';
  return accepted is not null;
end;
$$;

revoke all on function runspot_private.claim_environment_refresh(text,text),
  runspot_private.reserve_environment_attempt(text,text,uuid),
  runspot_private.complete_environment_refresh(text,uuid,jsonb,integer,text) from public,anon,authenticated;
grant execute on function runspot_private.claim_environment_refresh(text,text),
  runspot_private.reserve_environment_attempt(text,text,uuid),
  runspot_private.complete_environment_refresh(text,uuid,jsonb,integer,text) to service_role;

create function public.claim_environment_refresh(requested_key text, requested_slot text)
returns jsonb language sql security invoker set search_path = '' as $$
  select runspot_private.claim_environment_refresh(requested_key,requested_slot);
$$;
create function public.reserve_environment_attempt(requested_provider text, requested_key text, token uuid)
returns text language sql security invoker set search_path = '' as $$
  select runspot_private.reserve_environment_attempt(requested_provider,requested_key,token);
$$;
create function public.complete_environment_refresh(requested_key text, token uuid, cache_payload jsonb, ttl_seconds integer, error_code text)
returns boolean language sql security invoker set search_path = '' as $$
  select runspot_private.complete_environment_refresh(requested_key,token,cache_payload,ttl_seconds,error_code);
$$;
revoke all on function public.claim_environment_refresh(text,text),
  public.reserve_environment_attempt(text,text,uuid),
  public.complete_environment_refresh(text,uuid,jsonb,integer,text) from public,anon,authenticated;
grant execute on function public.claim_environment_refresh(text,text),
  public.reserve_environment_attempt(text,text,uuid),
  public.complete_environment_refresh(text,uuid,jsonb,integer,text) to service_role;
notify pgrst, 'reload schema';
