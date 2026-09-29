-- 격리된 빈 PostgreSQL에서만 사용하는 Supabase 인증 대역입니다.
-- 실제 Supabase에는 실행하지 않습니다.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users(
  id uuid primary key,
  phone text,
  phone_confirmed_at timestamptz,
  phone_change text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
