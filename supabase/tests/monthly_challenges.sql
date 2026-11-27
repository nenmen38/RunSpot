\set ON_ERROR_STOP on
begin;
create function pg_temp.check_ch(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-0000-0000-000000000a91','ch91@example.com',now());
-- 2025년 12월: 1~12일 매일 5km(주말 4번 포함: 6·7·13일 아님 → 6,7일 토·일 + 1~12 중 토일은 6·7일뿐) → 주말은 따로 2번 더합니다.
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status)
select '00000000-0000-0000-0000-000000000a91',gen_random_uuid(),
  ('2025-12-01 07:00'::timestamp + (d*interval '1 day')) at time zone 'Asia/Seoul',
  ('2025-12-01 07:30'::timestamp + (d*interval '1 day')) at time zone 'Asia/Seoul',5000,1800,'verified'
from generate_series(0,11) d;
-- 12-13(토)·12-14(일) 주말 러닝 추가 → 주말 4번(6·7·13·14일)
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec,integrity_status) values
 ('00000000-0000-0000-0000-000000000a91',gen_random_uuid(),'2025-12-13 07:00+09','2025-12-13 07:30+09',3000,1800,'verified'),
 ('00000000-0000-0000-0000-000000000a91',gen_random_uuid(),'2025-12-14 07:00+09','2025-12-14 07:30+09',3000,1800,'verified');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000a91',true);
select public.my_challenges('2025-12-20') as c \gset
select pg_temp.check_ch((:'c'::jsonb->>'all_done')::boolean,'12월 챌린지 모두 완료');
select pg_temp.check_ch((:'c'::jsonb->'challenges'->0->>'progress')::int=50000,'거리는 목표에서 멈춤');
select pg_temp.check_ch((:'c'::jsonb->'challenges'->1->>'progress')::int=4,'주말 4번');
select pg_temp.check_ch((:'c'::jsonb->'challenges'->2->>'progress')::int=10,'10일');
select pg_temp.check_ch(:'c'::jsonb->>'reward_item'='char_cap_santa','12월 보상');
select pg_temp.check_ch((:'c'::jsonb->>'completed_months')::int=1,'완료한 달 1');
select pg_temp.check_ch(public.my_wallet()->'cosmetics'->'owned' ? 'char_cap_santa','산타 러닝캡 선물');
select pg_temp.check_ch(public.equip_cosmetic('char_head','char_cap_santa')->'cosmetics'->'equipped'->>'char_head'='char_cap_santa','산타 모자 착용');
-- 2025년 11월: 기록 없음 → 진행 0, 보상 없음
select public.my_challenges('2025-11-03') as n \gset
select pg_temp.check_ch(not (:'n'::jsonb->>'all_done')::boolean and :'n'::jsonb->'reward_item'='null'::jsonb
  and (:'n'::jsonb->'challenges'->0->>'progress')::int=0,'11월은 미완료');
select pg_temp.check_ch(pg_temp.fails($q$select public.my_challenges((now()+interval '40 days')::date)$q$,'22023'),'미래 달 거절');
select pg_temp.check_ch(pg_temp.fails($q$select public.buy_cosmetic('char_cap_santa',null)$q$,'22023'),'산타 모자는 못 삼');
reset role;
rollback;
