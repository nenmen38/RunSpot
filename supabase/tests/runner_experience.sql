\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-0000-0000-000000000391','goal391@example.com',now()),
('00000000-0000-0000-0000-000000000392','goal392@example.com',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000391',true);
select public.my_weekly_goal(true,20);
do $$ begin if public.my_weekly_goal()<>20 then raise exception '목표 저장 실패'; end if; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000392',true);
do $$ begin if public.my_weekly_goal() is not null then raise exception '다른 계정 목표 노출'; end if; end $$;
select public.my_weekly_goal(true,5);
select public.my_weekly_goal(true,null);
do $$ begin if public.my_weekly_goal() is not null then raise exception '목표 삭제 실패'; end if; end $$;
rollback;
