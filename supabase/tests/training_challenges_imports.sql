\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(ok boolean,message text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,code text) returns boolean language plpgsql as $$ begin execute statement;return false;exception when others then return sqlstate=code;end;$$;
\set owner '00000000-0000-0000-0000-000000000411'
\set member '00000000-0000-0000-0000-000000000412'
\set outsider '00000000-0000-0000-0000-000000000413'
\set crew '00000000-0000-0000-0000-000000000414'
\set challenge '00000000-0000-0000-0000-000000000415'
insert into auth.users(id,email,email_confirmed_at) values(:'owner','training411@example.com',now()),(:'member','training412@example.com',now()),(:'outsider','training413@example.com',now());
update public.profiles set nickname='훈련검증'||right(id::text,3) where id in (:'owner',:'member',:'outsider');
insert into runspot_private.crews(id,owner_id,name,icon) values(:'crew',:'owner','검증크루','bolt');
insert into runspot_private.crew_members(crew_id,user_id,role) values(:'crew',:'owner','owner'),(:'crew',:'member','member');
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec) values(:'owner',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',5000,1800) returning id as run \gset
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select public.training_plan('start','habit',current_date-1);
select public.training_plan('complete',session_index=>0,run_id=>:'run');
select pg_temp.ok(jsonb_array_length(public.training_plan()->'completed')=1,'훈련 기록 연결');
select public.training_plan('undo',session_index=>0);
select pg_temp.ok(jsonb_array_length(public.training_plan()->'completed')=0,'훈련 연결 해제');
select public.crew_challenge(:'crew','create',:'challenge',100,30);
select public.crew_challenge(:'crew','join',:'challenge');
select set_config('request.jwt.claim.sub',:'member',true);
select pg_temp.ok(public.training_plan() is null,'타인 계획 비공개');
select public.training_plan('start','5k',current_date-1);
select pg_temp.ok(pg_temp.fails(format('select public.training_plan(''complete'',session_index=>0,run_id=>%L)',:'run'),'42501'),'타인 기록 연결 금지');
select pg_temp.ok(pg_temp.fails(format('select public.crew_challenge(%L,''create'',gen_random_uuid(),100,30)',:'crew'),'42501'),'크루원 생성 금지');
select public.crew_challenge(:'crew','join',:'challenge');
select set_config('request.jwt.claim.sub',:'outsider',true);
select pg_temp.ok(pg_temp.fails(format('select public.crew_challenge(%L)',:'crew'),'42501'),'외부인 목표 조회 금지');
select public.external_runs('import',jsonb_build_object('source','file','source_id','test-import','started_at',now()-interval '1 hour','ended_at',now(),'distance_m',5000,'duration_sec',1800,'route','[]'::jsonb));
select public.external_runs('import',jsonb_build_object('source','file','source_id','test-import','started_at',now()-interval '1 hour','ended_at',now(),'distance_m',5000,'duration_sec',1800,'route','[]'::jsonb));
select pg_temp.ok(jsonb_array_length(public.external_runs())=1,'외부 기록 중복 방지');
select public.external_runs()->0->>'id' as external \gset
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.ok(jsonb_array_length(public.external_runs())=0,'외부 기록 계정 격리');
select public.external_runs('delete',requested_id=>:'external');
select set_config('request.jwt.claim.sub',:'outsider',true);
select pg_temp.ok(jsonb_array_length(public.external_runs())=1,'타인 기록 삭제 금지');
reset role;
select pg_temp.ok(not exists(select 1 from public.runs where user_id=:'outsider'),'가져온 기록은 보상 테이블과 분리');
-- 가입 전 기록은 공동 목표에 반영되지 않습니다.
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.ok((public.crew_challenge(:'crew')->0->>'distance_m')::int=0,'참여 전 기록 합산 금지');
rollback;
