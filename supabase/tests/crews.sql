\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
create function pg_temp.invite_note() returns jsonb language sql as $$
  select n from jsonb_array_elements(public.my_notifications()) n where n->>'kind'='crew_invite' limit 1;
$$;
grant execute on function pg_temp.invite_note() to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000221','crew221@example.com',now()),
 ('00000000-0000-0000-0000-000000000222','crew222@example.com',now()),
 ('00000000-0000-0000-0000-000000000223','crew223@example.com',now()),
 ('00000000-0000-0000-0000-000000000224','crew224@example.com',now());
update public.profiles set nickname='크루검증'||right(id::text,3),visibility='friends' where id::text like '%00000000022_';
insert into public.friendships(user_low,user_high,requested_by,status) values
 ('00000000-0000-0000-0000-000000000221','00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000221','accepted'),
 ('00000000-0000-0000-0000-000000000221','00000000-0000-0000-0000-000000000223','00000000-0000-0000-0000-000000000221','accepted');
insert into runspot_private.coin_grants(user_id,coins,reason) values
 ('00000000-0000-0000-0000-000000000221',1000,'테스트'),('00000000-0000-0000-0000-000000000224',1000,'테스트');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000221',true);
select pg_temp.assert_true((select (w->'prices'->>'crew_ticket')::int=640 and (w->>'crew_tickets')::int=0
  and not (w->>'in_crew')::boolean from (select public.my_wallet() w) x),'생성권 가격 표시');
select pg_temp.assert_true(pg_temp.fails('select public.create_crew(''새벽런'','''',''bolt'')','P0001'),'생성권 없이 생성 거부');

-- 생성권은 640코인이고, 쓰지 않은 생성권이 있으면 더 사지 않습니다.
select pg_temp.assert_true((select (w->>'coins')::int=360 and (w->>'crew_tickets')::int=1
  from (select public.buy_crew_ticket() w) x),'생성권 구매');
select pg_temp.assert_true(pg_temp.fails('select public.buy_crew_ticket()','P0001'),'생성권 중복 구매 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_crew(''가'','''',''bolt'')','22023'),'짧은 이름 거부');
select pg_temp.assert_true(pg_temp.fails('select public.create_crew(''새벽런'','''',''rocket'')','22023'),'없는 아이콘 거부');
select pg_temp.assert_true(pg_temp.fails(format('select public.create_crew(''새벽런'',%L,''bolt'')',repeat('가',61)),'22023'),'긴 설명 거부');
select pg_temp.assert_true((select c->'crew'->>'name'='새벽런' and c->'crew'->>'icon'='flame'
  and (c->'crew'->>'is_owner')::boolean and jsonb_array_length(c->'crew'->'members')=1
  and c->'crew'->'members'->0->>'role'='owner'
  from (select public.create_crew(' 새벽런 ',' 매일 아침 한강 5km ','flame') c) x),'크루 생성');
select pg_temp.assert_true((select (w->>'crew_tickets')::int=0 and (w->>'in_crew')::boolean
  from (select public.my_wallet() w) x),'생성권 사용');

-- 같은 이름(대소문자 무시)은 다른 사람이 쓸 수 없습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000224',true);
select public.buy_crew_ticket();
select pg_temp.assert_true(pg_temp.fails('select public.create_crew(''새벽런'','''',''bolt'')','P0001'),'같은 이름 거부');
select public.create_crew('Night Run','','star');
reset role;
select id as dawn from runspot_private.crews where name='새벽런' \gset
select id as night from runspot_private.crews where name='Night Run' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000221',true);

-- 크루장만, 친구에게만 초대할 수 있습니다.
select pg_temp.assert_true(pg_temp.fails('select public.invite_to_crew(''00000000-0000-0000-0000-000000000224'')','42501'),'친구 아닌 사용자 초대 거부');
select pg_temp.assert_true(pg_temp.fails('select public.invite_to_crew(''00000000-0000-0000-0000-000000000221'')','42501'),'자기 자신 초대 거부');
select pg_temp.assert_true((public.invite_to_crew('00000000-0000-0000-0000-000000000222')->'crew'->'pending')
  ='["00000000-0000-0000-0000-000000000222"]'::jsonb,'친구 초대');
select public.invite_to_crew('00000000-0000-0000-0000-000000000222');
select public.invite_to_crew('00000000-0000-0000-0000-000000000223');

-- 초대받은 친구는 알림과 크루 탭에서 초대를 보고 수락합니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000222',true);
select pg_temp.assert_true(pg_temp.fails('select public.invite_to_crew(''00000000-0000-0000-0000-000000000221'')','42501'),'크루장 아닌 사람 초대 거부');
select pg_temp.assert_true((select n->>'crew_name'='새벽런' and n->>'nickname'='크루검증221'
  and n->>'invite_status'='invited' and (n->>'can_respond')::boolean
  from (select pg_temp.invite_note() n) x) and public.unread_notification_count()=1,'크루 초대 알림 한 번');
select pg_temp.assert_true((select c->'crew'='null'::jsonb and c->'invites'->0->>'name'='새벽런'
  and c->'invites'->0->>'inviter'='크루검증221' from (select public.my_crew() c) x),'받은 초대 표시');
select pg_temp.assert_true((select c->'crew'->>'name'='새벽런' and not (c->'crew'->>'is_owner')::boolean
  and jsonb_array_length(c->'crew'->'members')=2 and c->'invites'='[]'::jsonb
  from (select public.respond_crew_invite(:'dawn',true) c) x),'초대 수락');
select pg_temp.assert_true(pg_temp.fails(format('select public.respond_crew_invite(%L,true)',:'dawn'),'P0001'),'중복 수락 거부');
select pg_temp.assert_true((select n->>'invite_status'='accepted' and not (n->>'can_respond')::boolean
  from (select pg_temp.invite_note() n) x),'수락 후 알림 상태');
-- 크루원은 크루원 목록을 보지만 대기 중 초대는 보지 못합니다.
select pg_temp.assert_true((public.my_crew()->'crew'->'pending')='[]'::jsonb,'크루원에게 대기 초대 비공개');

-- 거절하면 크루에 들어가지 않고, 크루장이 다시 초대할 수 있습니다.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000223',true);
select public.respond_crew_invite(:'dawn',false);
select pg_temp.assert_true((public.my_crew()->'crew')='null'::jsonb,'거절');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000221',true);
select pg_temp.assert_true(pg_temp.fails('select public.invite_to_crew(''00000000-0000-0000-0000-000000000222'')','P0001'),'이미 크루원인 친구 초대 거부');
select public.invite_to_crew('00000000-0000-0000-0000-000000000223');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000223',true);
select pg_temp.assert_true((select n->>'invite_status'='invited' and not (n->>'read')::boolean
  from (select pg_temp.invite_note() n) x),'다시 초대하면 새 알림');

-- 다른 크루의 초대는 이미 크루에 속하면 수락할 수 없습니다.
reset role;
insert into runspot_private.crew_invites(crew_id,user_id,invited_by)
select id,'00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000224' from runspot_private.crews where name='Night Run';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000222',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.respond_crew_invite(%L,true)',:'night'),'P0001'),'두 크루 가입 거부');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.crews','42501'),'크루 원본 접근 거부');

-- 생성권 구매는 코인 잔액에서 빠집니다.
reset role;
select pg_temp.assert_true(runspot_private.coin_balance('00000000-0000-0000-0000-000000000221')=360,'잔액 반영');
-- 크루장이 탈퇴하면 크루와 크루원 연결, 초대 알림이 함께 지워집니다.
delete from auth.users where id='00000000-0000-0000-0000-000000000221';
select pg_temp.assert_true((select count(*)=0 from runspot_private.crew_members where user_id='00000000-0000-0000-0000-000000000222')
  and (select count(*)=0 from runspot_private.notifications where kind='crew_invite'
    and recipient_id in ('00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000223')),'크루장 탈퇴 정리');
rollback;
