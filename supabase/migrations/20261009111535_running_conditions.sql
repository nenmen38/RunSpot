-- 공개 관측 자료만 공동 보관하며 사용자 좌표는 저장하지 않습니다.
create table runspot_private.environment_cache (
  cache_key text primary key check (length(cache_key) between 1 and 180),
  payload jsonb not null,
  expires_at timestamptz not null
);
create index environment_cache_expiry on runspot_private.environment_cache(expires_at);
create table runspot_private.environment_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  last_request timestamptz not null,
  request_count integer not null check (request_count between 1 and 120)
);
alter table runspot_private.environment_cache enable row level security;
alter table runspot_private.environment_limits enable row level security;
revoke all on runspot_private.environment_cache, runspot_private.environment_limits from public, anon, authenticated;

create function runspot_private.consume_environment_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); accepted uuid;
begin
  if owner_id is null or not runspot_private.is_active(owner_id) then
    raise exception '계정 이용 권한을 확인해 주세요.' using errcode='42501';
  end if;
  insert into runspot_private.environment_limits as limits(user_id,window_start,last_request,request_count)
  values(owner_id,now(),now(),1)
  on conflict(user_id) do update set
    window_start=case when limits.window_start <= now()-interval '1 hour' then now() else limits.window_start end,
    request_count=case when limits.window_start <= now()-interval '1 hour' then 1 else limits.request_count+1 end,
    last_request=now()
  where limits.last_request <= now()-interval '10 seconds'
    and (limits.window_start <= now()-interval '1 hour' or limits.request_count<120)
  returning user_id into accepted;
  return accepted is not null;
end;
$$;
create function runspot_private.read_environment_cache(requested_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select payload from runspot_private.environment_cache where cache_key=requested_key and expires_at>now();
$$;
create function runspot_private.write_environment_cache(requested_key text, cache_payload jsonb, ttl_seconds integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if requested_key is null or length(requested_key) not between 1 and 180
    or cache_payload is null or pg_column_size(cache_payload)>2000000
    or ttl_seconds is null or ttl_seconds not between 1 and 86400 then
    raise exception '관측 자료 보관 요청이 올바르지 않습니다.' using errcode='22023';
  end if;
  delete from runspot_private.environment_cache where expires_at<=now();
  insert into runspot_private.environment_cache(cache_key,payload,expires_at)
  values(requested_key,cache_payload,now()+make_interval(secs=>ttl_seconds))
  on conflict(cache_key) do update set payload=excluded.payload,expires_at=excluded.expires_at;
end;
$$;
revoke all on function runspot_private.consume_environment_request(), runspot_private.read_environment_cache(text),
  runspot_private.write_environment_cache(text,jsonb,integer) from public,anon,authenticated;
grant execute on function runspot_private.consume_environment_request() to authenticated;
grant usage on schema runspot_private to service_role;
grant execute on function runspot_private.read_environment_cache(text),runspot_private.write_environment_cache(text,jsonb,integer) to service_role;
create function public.consume_environment_request()
returns boolean language sql security invoker set search_path = '' as $$
  select runspot_private.consume_environment_request();
$$;
create function public.read_environment_cache(requested_key text)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select runspot_private.read_environment_cache(requested_key);
$$;
create function public.write_environment_cache(requested_key text, cache_payload jsonb, ttl_seconds integer)
returns void language sql security invoker set search_path = '' as $$
  select runspot_private.write_environment_cache(requested_key,cache_payload,ttl_seconds);
$$;
revoke all on function public.consume_environment_request(), public.read_environment_cache(text),
  public.write_environment_cache(text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.consume_environment_request() to authenticated;
grant execute on function public.read_environment_cache(text),public.write_environment_cache(text,jsonb,integer) to service_role;
notify pgrst, 'reload schema';
