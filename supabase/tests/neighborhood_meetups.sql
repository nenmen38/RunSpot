\set ON_ERROR_STOP on
begin;
create function pg_temp.check_meetup(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=code; end; $$;
\set host '00000000-0000-0000-0000-000000000401'
\set member '00000000-0000-0000-0000-000000000402'
\set other '00000000-0000-0000-0000-000000000403'
\set meetup '00000000-0000-0000-0000-000000000404'
insert into auth.users(id,email,email_confirmed_at) values
(:'host','meet401@example.com',now()),(:'member','meet402@example.com',now()),(:'other','meet403@example.com',now());
update public.profiles set nickname='모임검증'||right(id::text,3) where id in (:'host',:'member',:'other');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'host',true);
select public.meetup_create(:'meetup','하양 아침 달리기','경산 하양','하양역 광장',now()+interval '20 minutes',5,360,2);
select public.meetup_create_with_tags(:'meetup','하양 아침 달리기','경산 하양','하양역 광장',
  now()+interval '20 minutes',5,360,2,true,true,false,true);
select pg_temp.check_meetup(public.meetup_list_with_tags('하양',360,false,0,array['beginner','walk_run'])
  @> '[{"beginner_friendly":true,"walk_run":true,"waits_for_group":true}]','모임 안내 저장 및 필터');
select pg_temp.check_meetup(public.meetup_list_with_tags('하양',360,false,0,array['women'])='[]','선택하지 않은 태그 제외');
select public.meetup_create(:'meetup','하양 아침 달리기','경산 하양','하양역 광장',now()+interval '20 minutes',5,360,2);
select pg_temp.check_meetup(jsonb_array_length(public.meetup_list('하양',360))=1,'지역과 페이스 검색');
select pg_temp.check_meetup(jsonb_array_length(public.meetup_list('하양',480))=0,'다른 페이스 제외');
select set_config('request.jwt.claim.sub',:'member',true);
select public.meetup_action(:'meetup','join');
select public.meetup_action(:'meetup','join');
select pg_temp.check_meetup(pg_temp.fails(format('select public.meetup_action(%L,''cancel'')',:'meetup'),'42501'),'참가자 취소 권한');
select set_config('request.jwt.claim.sub',:'other',true);
select pg_temp.check_meetup(pg_temp.fails(format('select public.meetup_action(%L,''join'')',:'meetup'),'22023'),'정원 초과 차단');
select set_config('request.jwt.claim.sub',:'member',true);
select public.meetup_action(:'meetup','leave');
select public.meetup_action(:'meetup','join');
select set_config('request.jwt.claim.sub',:'host',true);
select public.meetup_action(:'meetup','prepare') as group_id \gset
select pg_temp.check_meetup(public.meetup_action(:'meetup','prepare')=:'group_id'::uuid,'출발 준비 재시도 중복 방지');
reset role;
select pg_temp.check_meetup((select count(*)=2 from runspot_private.running_group_members where group_id=:'group_id'),'동의한 참가자 연결');
insert into runspot_private.blocks(blocker_id,blocked_id) values(:'other',:'host');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'other',true);
select pg_temp.check_meetup(jsonb_array_length(public.meetup_list())=0,'차단한 주최자 비공개');
select pg_temp.check_meetup(public.meetup_list_with_tags('',null,false,0,array['beginner'])='[]','태그 목록도 차단 적용');
select pg_temp.check_meetup(pg_temp.fails(format('select public.meetup_action(%L,''join'')',:'meetup'),'42501'),'차단 우회 참가 방지');
rollback;
