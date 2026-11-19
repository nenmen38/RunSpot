\set ON_ERROR_STOP on
begin;
create function pg_temp.check_photo(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000331','photo331@example.com',now()),
 ('00000000-0000-0000-0000-000000000332','photo332@example.com',now()),
 ('00000000-0000-0000-0000-000000000333','photo333@example.com',now());
update public.profiles set nickname='사진'||right(id::text,3),visibility='friends' where id::text like '%00000000033_';
insert into runspot_private.crews(owner_id,name,icon) values('00000000-0000-0000-0000-000000000331','사진크루','star');
select id as crew from runspot_private.crews where name='사진크루' \gset
insert into runspot_private.crew_members(user_id,crew_id,role) values
 ('00000000-0000-0000-0000-000000000331',:'crew','owner'),('00000000-0000-0000-0000-000000000332',:'crew','member');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000331',true);
select public.crew_chat_room(:'crew') as room \gset
-- 가짜 JPEG(FF D8 ... FF D9)
select encode('\xffd8000102ffd9'::bytea,'base64') as jpeg \gset
select pg_temp.check_photo(pg_temp.fails(format('select public.chat_room_send_photo(%L,%L,gen_random_uuid())',:'room',encode('\x89504e47'::bytea,'base64')),'22023'),'JPEG 아니면 거부');
select public.chat_room_send_photo(:'room',:'jpeg','00000000-0000-0000-0000-000000000051');
select public.chat_room_send_photo(:'room',:'jpeg','00000000-0000-0000-0000-000000000051');
select public.chat_room_read(:'room') as data \gset
select pg_temp.check_photo(jsonb_array_length(:'data'::jsonb->'messages')=1
  and :'data'::jsonb->'messages'->0->>'kind'='photo' and :'data'::jsonb->'messages'->0->>'body'='사진','사진 메시지·중복 없음');
-- 크루원은 사진을 받고, 크루원이 아니면 거부합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000332',true);
select pg_temp.check_photo(public.chat_room_photo(:'room',(:'data'::jsonb->'messages'->0->>'id')::bigint)=:'jpeg','크루원 사진 받기');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000333',true);
select pg_temp.check_photo(pg_temp.fails(format('select public.chat_room_photo(%L,1)',:'room'),'42501'),'비참여자 거부');
-- 1분에 5장까지
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000331',true);
select public.chat_room_send_photo(:'room',:'jpeg',gen_random_uuid()) from generate_series(1,4);
select pg_temp.check_photo(pg_temp.fails(format('select public.chat_room_send_photo(%L,%L,gen_random_uuid())',:'room',:'jpeg'),'P0001'),'사진 전송 한도');
rollback;
