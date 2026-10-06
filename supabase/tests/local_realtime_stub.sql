-- 격리된 로컬 PostgreSQL 테스트 전용이며 실제 Supabase에는 적용하지 않습니다.
create schema realtime;
create table realtime.messages (id bigint generated always as identity,extension text,payload jsonb);
alter table realtime.messages enable row level security;
grant usage on schema realtime to authenticated;
grant select on realtime.messages to authenticated;
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic',true);
$$;
create function realtime.send(payload jsonb,event text,topic text,private boolean)
returns void language sql as $$
  insert into realtime.messages(extension,payload) values('broadcast',payload);
$$;
