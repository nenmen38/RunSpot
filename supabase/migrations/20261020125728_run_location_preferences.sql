-- 러닝 자동 위치 공유 동의는 계정별로 저장하며 기본값은 꺼짐입니다.
create table public.run_location_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false
);
alter table public.run_location_preferences enable row level security;
revoke all on public.run_location_preferences from public,anon,authenticated;
grant select,insert,update on public.run_location_preferences to authenticated;
grant select,insert,update,delete on public.run_location_preferences to service_role;

create policy run_location_preferences_read on public.run_location_preferences
for select to authenticated
using (user_id=(select auth.uid()) and runspot_private.is_active((select auth.uid())));
create policy run_location_preferences_insert on public.run_location_preferences
for insert to authenticated
with check (user_id=(select auth.uid()) and runspot_private.is_active((select auth.uid())));
create policy run_location_preferences_update on public.run_location_preferences
for update to authenticated
using (user_id=(select auth.uid()) and runspot_private.is_active((select auth.uid())))
with check (user_id=(select auth.uid()) and runspot_private.is_active((select auth.uid())));
notify pgrst, 'reload schema';
