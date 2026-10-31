-- 토큰·발송 원본은 비공개 스키마에 보관하며 앱은 본인 전용 RPC만 사용합니다.
create table runspot_private.push_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 friend_request boolean not null default true,
 group_invite boolean not null default true,
 board_comment boolean not null default true
);
create table runspot_private.push_devices(
 id uuid primary key default gen_random_uuid(),
 token text unique not null check(length(token) between 20 and 4096),
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 platform text not null check(platform in ('android','ios')),
 registered_at timestamptz not null default now(),
 refreshed_at timestamptz not null default now()
);
create index push_devices_owner on runspot_private.push_devices(user_id);
create index push_devices_session on runspot_private.push_devices(session_id);
create table runspot_private.push_jobs(
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 actor_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('friend_request','group_invite','board_comment')),
 target_id uuid not null,
 source_key text unique not null,
 created_at timestamptz not null default now()
);
create index push_jobs_recipient on runspot_private.push_jobs(recipient_id);
create index push_jobs_actor on runspot_private.push_jobs(actor_id);
create index push_jobs_created on runspot_private.push_jobs(created_at);
create table runspot_private.push_deliveries(
 job_id uuid not null references runspot_private.push_jobs(id) on delete cascade,
 device_id uuid not null references runspot_private.push_devices(id) on delete cascade,
 attempts integer not null default 0,
 available_at timestamptz not null default now(),
 lease uuid,
 done boolean not null default false,
 primary key(job_id,device_id)
);
create index push_deliveries_device on runspot_private.push_deliveries(device_id);
create index push_deliveries_due on runspot_private.push_deliveries(available_at) where not done;
alter table runspot_private.push_preferences enable row level security;
alter table runspot_private.push_devices enable row level security;
alter table runspot_private.push_jobs enable row level security;
alter table runspot_private.push_deliveries enable row level security;
revoke all on runspot_private.push_preferences,runspot_private.push_devices,runspot_private.push_jobs,runspot_private.push_deliveries from public,anon,authenticated;

create function runspot_private.register_push_device(requested_token text,requested_platform text)
returns void language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); sid uuid:=(auth.jwt()->>'session_id')::uuid;
begin
 if viewer is null or not runspot_private.is_active(viewer) or not exists(select 1 from auth.sessions where id=sid and user_id=viewer) then
  raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 -- 계정 전환·토큰 갱신은 기존 세션의 연결을 제거한 뒤 같은 트랜잭션에서 등록합니다.
 delete from runspot_private.push_devices where session_id=sid and token<>requested_token;
 insert into runspot_private.push_devices(token,user_id,session_id,platform) values(requested_token,viewer,sid,requested_platform)
 on conflict(token) do update set registered_at=case
  when push_devices.user_id=excluded.user_id and push_devices.session_id=excluded.session_id then push_devices.registered_at else now() end,
 user_id=excluded.user_id,session_id=excluded.session_id,platform=excluded.platform,refreshed_at=now();
end;
$$;
create function runspot_private.unregister_push_device()
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 delete from runspot_private.push_devices where user_id=auth.uid() and session_id=(auth.jwt()->>'session_id')::uuid;
end;
$$;
create function runspot_private.my_push_preferences(friend_request boolean default null,group_invite boolean default null,board_comment boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare viewer uuid:=auth.uid(); result jsonb;
begin
 if viewer is null or not runspot_private.is_active(viewer) then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 insert into runspot_private.push_preferences as p(user_id,friend_request,group_invite,board_comment)
 values(viewer,coalesce(friend_request,true),coalesce(group_invite,true),coalesce(board_comment,true))
 on conflict(user_id) do update set friend_request=coalesce(my_push_preferences.friend_request,p.friend_request),
 group_invite=coalesce(my_push_preferences.group_invite,p.group_invite),board_comment=coalesce(my_push_preferences.board_comment,p.board_comment)
 returning to_jsonb(p)-'user_id' into result;
 return result;
end;
$$;
create function public.register_push_device(requested_token text,requested_platform text)
returns void language sql security invoker set search_path='' as $$ select runspot_private.register_push_device(requested_token,requested_platform); $$;
create function public.unregister_push_device() returns void language sql security invoker set search_path='' as $$ select runspot_private.unregister_push_device(); $$;
create function public.my_push_preferences(friend_request boolean default null,group_invite boolean default null,board_comment boolean default null)
returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.my_push_preferences(friend_request,group_invite,board_comment); $$;
revoke all on function runspot_private.register_push_device(text,text),runspot_private.unregister_push_device(),runspot_private.my_push_preferences(boolean,boolean,boolean),
 public.register_push_device(text,text),public.unregister_push_device(),public.my_push_preferences(boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function runspot_private.register_push_device(text,text),runspot_private.unregister_push_device(),runspot_private.my_push_preferences(boolean,boolean,boolean),
 public.register_push_device(text,text),public.unregister_push_device(),public.my_push_preferences(boolean,boolean,boolean) to authenticated;

create function runspot_private.enqueue_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='friendships' then
  if new.status<>'pending' then return null; end if;
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  values(case when new.requested_by=new.user_low then new.user_high else new.user_low end,new.requested_by,'friend_request',new.relationship_id,'friend:'||new.relationship_id)
  on conflict(source_key) do nothing;
 elsif tg_table_name='running_group_members' then
  if new.status<>'invited' then return null; end if;
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  select new.user_id,g.host_id,'group_invite',g.id,'group:'||g.id||':'||new.user_id from runspot_private.running_groups g where g.id=new.group_id
  on conflict(source_key) do nothing;
 elsif tg_table_name='notifications' then
  if new.kind not in ('comment','reply') then return null; end if;
  insert into runspot_private.push_jobs(recipient_id,actor_id,kind,target_id,source_key)
  values(new.recipient_id,new.actor_id,'board_comment',new.post_id,'comment:'||new.id) on conflict(source_key) do nothing;
 end if;
 return null;
end;
$$;
create trigger friendships_push after insert on public.friendships for each row execute function runspot_private.enqueue_push();
create trigger group_invites_push after insert on runspot_private.running_group_members for each row execute function runspot_private.enqueue_push();
create trigger board_comments_push after insert on runspot_private.notifications for each row execute function runspot_private.enqueue_push();
revoke all on function runspot_private.enqueue_push() from public,anon,authenticated;

-- 큐를 만든 뒤에도 차단·공개 범위·취소·수신 설정을 발송 직전에 다시 검사합니다.
create function runspot_private.push_allowed(j runspot_private.push_jobs)
returns boolean language sql stable security definer set search_path='' as $$
 select runspot_private.is_active(j.recipient_id) and runspot_private.is_active(j.actor_id)
 and not exists(select 1 from runspot_private.blocks where (blocker_id=j.actor_id and blocked_id=j.recipient_id) or (blocker_id=j.recipient_id and blocked_id=j.actor_id))
 and coalesce((select case j.kind when 'friend_request' then p.friend_request when 'group_invite' then p.group_invite else p.board_comment end
  from runspot_private.push_preferences p where p.user_id=j.recipient_id),true)
 and case j.kind
 when 'friend_request' then exists(select 1 from public.friendships f where f.relationship_id=j.target_id and f.status='pending' and f.requested_by=j.actor_id)
 when 'group_invite' then exists(select 1 from runspot_private.running_groups g join runspot_private.running_group_members m on m.group_id=g.id
  where g.id=j.target_id and g.state='lobby' and g.expires_at>now() and m.user_id=j.recipient_id and m.status='invited')
 else exists(select 1 from runspot_private.notifications n where 'comment:'||n.id=j.source_key and runspot_private.notification_visible(n,j.recipient_id)) end;
$$;
revoke all on function runspot_private.push_allowed(runspot_private.push_jobs) from public,anon,authenticated;
create function runspot_private.claim_push_deliveries()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 delete from runspot_private.push_jobs where created_at<now()-interval '1 day';
 delete from runspot_private.push_devices where refreshed_at<now()-interval '30 days';
 insert into runspot_private.push_deliveries(job_id,device_id)
 select j.id,d.id from runspot_private.push_jobs j join runspot_private.push_devices d on d.user_id=j.recipient_id
 where j.created_at>now()-interval '15 minutes' and d.registered_at<=j.created_at and runspot_private.push_allowed(j)
 on conflict do nothing;
 with candidates as (
  select q.job_id,q.device_id from runspot_private.push_deliveries q
  join runspot_private.push_jobs j on j.id=q.job_id join runspot_private.push_devices d on d.id=q.device_id
  where not q.done and q.attempts<5 and q.available_at<=now() and j.created_at>now()-interval '15 minutes'
   and d.user_id=j.recipient_id and runspot_private.push_allowed(j)
  order by q.available_at limit 20 for update of q skip locked
 ), claimed as (
  update runspot_private.push_deliveries q set attempts=q.attempts+1,lease=gen_random_uuid(),available_at=now()+interval '2 minutes'
  from candidates c where q.job_id=c.job_id and q.device_id=c.device_id returning q.*
 ) select coalesce(jsonb_agg(jsonb_build_object('job_id',q.job_id,'device_id',q.device_id,'lease',q.lease,'token',d.token,
  'recipient_id',j.recipient_id,'kind',j.kind,'target_id',j.target_id)),'[]') into result
 from claimed q join runspot_private.push_jobs j on j.id=q.job_id join runspot_private.push_devices d on d.id=q.device_id;
 return result;
end;
$$;
create function runspot_private.finish_push_delivery(job_id uuid,device_id uuid,lease uuid,outcome text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if outcome not in ('sent','retry','invalid','failed') or outcome is null then raise exception '발송 결과를 확인해 주세요.'; end if;
 update runspot_private.push_deliveries q set done=outcome<>'retry',available_at=now()+interval '2 minutes' * q.attempts
 where q.job_id=finish_push_delivery.job_id and q.device_id=finish_push_delivery.device_id and q.lease=finish_push_delivery.lease;
 if found and outcome='invalid' then delete from runspot_private.push_devices where id=finish_push_delivery.device_id; end if;
end;
$$;

-- 미사용 사진을 먼저 격리합니다. 게시글 저장과 같은 객체 잠금을 사용하여 삭제 중 재첨부를 막습니다.
create table runspot_private.board_photo_cleanup(
 path text primary key,
 claimed_at timestamptz not null default now()
);
alter table runspot_private.board_photo_cleanup enable row level security;
revoke all on runspot_private.board_photo_cleanup from public,anon,authenticated;
create function runspot_private.protect_board_photos()
returns trigger language plpgsql security definer set search_path='' as $$
declare photo_path text;
begin
 for photo_path in select x from unnest(new.image_paths) x order by x loop
  perform pg_advisory_xact_lock(hashtextextended('board_photo:'||photo_path,0));
  if exists(select 1 from runspot_private.board_photo_cleanup c where c.path=photo_path)
   or not exists(select 1 from storage.objects o where o.bucket_id='board-images' and o.name=photo_path) then
   raise exception '만료되었거나 없는 사진입니다. 다시 첨부해 주세요.' using errcode='22023'; end if;
 end loop;
 return new;
end;
$$;
create trigger board_photos_protect before insert or update of image_paths on runspot_private.board_posts
 for each row execute function runspot_private.protect_board_photos();
revoke all on function runspot_private.protect_board_photos() from public,anon,authenticated;
create function runspot_private.claim_unused_board_photos()
returns jsonb language plpgsql security definer set search_path='' as $$
declare item record; paths jsonb:='[]';
begin
 -- 파일 제거가 완료된 경로의 격리 정보만 정리합니다.
 delete from runspot_private.board_photo_cleanup c where not exists(select 1 from storage.objects o where o.bucket_id='board-images' and o.name=c.path);
 for item in select o.name from storage.objects o where o.bucket_id='board-images' and o.created_at<now()-interval '24 hours'
  and not exists(select 1 from runspot_private.board_posts p where p.image_paths @> array[o.name])
  and not exists(select 1 from runspot_private.board_reports r where coalesce(r.snapshot->'images','[]'::jsonb) ? o.name)
  order by o.created_at limit 100 loop
  perform pg_advisory_xact_lock(hashtextextended('board_photo:'||item.name,0));
  if not exists(select 1 from runspot_private.board_posts p where p.image_paths @> array[item.name])
   and not exists(select 1 from runspot_private.board_reports r where coalesce(r.snapshot->'images','[]'::jsonb) ? item.name) then
   insert into runspot_private.board_photo_cleanup(path) values(item.name) on conflict do nothing;
   paths:=paths||jsonb_build_array(item.name);
  end if;
 end loop;
 return paths;
end;
$$;
create function public.claim_push_deliveries() returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.claim_push_deliveries(); $$;
create function public.finish_push_delivery(job_id uuid,device_id uuid,lease uuid,outcome text) returns void language sql security invoker set search_path='' as $$ select runspot_private.finish_push_delivery(job_id,device_id,lease,outcome); $$;
create function public.claim_unused_board_photos() returns jsonb language sql security invoker set search_path='' as $$ select runspot_private.claim_unused_board_photos(); $$;
revoke all on function runspot_private.claim_push_deliveries(),runspot_private.finish_push_delivery(uuid,uuid,uuid,text),runspot_private.claim_unused_board_photos() from public,anon,authenticated;
grant execute on function runspot_private.claim_push_deliveries(),runspot_private.finish_push_delivery(uuid,uuid,uuid,text),runspot_private.claim_unused_board_photos() to service_role;
revoke all on function public.claim_push_deliveries(),public.finish_push_delivery(uuid,uuid,uuid,text),public.claim_unused_board_photos() from public,anon,authenticated;
grant execute on function public.claim_push_deliveries(),public.finish_push_delivery(uuid,uuid,uuid,text),public.claim_unused_board_photos() to service_role;
notify pgrst,'reload schema';

create table runspot_private.operations_worker_config(
 singleton boolean primary key default true check(singleton),
 endpoint text not null check(endpoint ~ '^https://[^[:space:]]+/functions/v1/operations-worker$'),
 secret text not null check(length(secret)>=32)
);
alter table runspot_private.operations_worker_config enable row level security;
revoke all on runspot_private.operations_worker_config from public,anon,authenticated,service_role;
create table runspot_private.operations_worker_state(
 singleton boolean primary key default true check(singleton),
 attempted_at timestamptz,
 succeeded_at timestamptz,
 last_status integer
);
alter table runspot_private.operations_worker_state enable row level security;
revoke all on runspot_private.operations_worker_state from public,anon,authenticated;
insert into runspot_private.operations_worker_state(singleton) values(true);
create function runspot_private.run_operations_worker()
returns void language plpgsql set search_path='' as $$
declare config runspot_private.operations_worker_config; response extensions.http_response;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('runspot_operations_worker',0)) then return; end if;
 select * into config from runspot_private.operations_worker_config where singleton;
 if not found then return; end if;
 update runspot_private.operations_worker_state set attempted_at=clock_timestamp() where singleton;
 begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','55000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  select * into response from extensions.http((
   'POST',config.endpoint,array[extensions.http_header('x-worker-secret',config.secret)],'application/json','{}'
  )::extensions.http_request);
  update runspot_private.operations_worker_state set last_status=response.status,
   succeeded_at=case when response.status=200 then clock_timestamp() else succeeded_at end where singleton;
 exception when others then
  update runspot_private.operations_worker_state set last_status=0 where singleton;
 end;
end;
$$;
revoke all on function runspot_private.run_operations_worker() from public,anon,authenticated,service_role;
select cron.schedule('runspot-operations-worker','* * * * *','select runspot_private.run_operations_worker();');
