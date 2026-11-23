\set ON_ERROR_STOP on
begin;
\set writer '00000000-0000-0000-0000-000000000461'
\set reader '00000000-0000-0000-0000-000000000462'
\set staff '00000000-0000-0000-0000-000000000463'
create function pg_temp.check_report(ok boolean) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '프로필 사진 신고 검증 실패'; end if; end; $$;
create function pg_temp.denied(statement text,expected text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
(:'writer','writer461@example.com',now()),(:'reader','reader462@example.com',now()),(:'staff','staff463@example.com',now());
update public.profiles set nickname='사진검증'||right(id::text,3) where id in (:'writer',:'reader',:'staff');
insert into runspot_private.user_roles(user_id,role) values(:'staff','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub',:'writer',true);
select public.set_my_avatar('/9gB/9k=');
select set_config('request.jwt.claim.sub',:'reader',true);
select public.reportable_avatar(:'writer')->>'version' as original \gset
-- 신고 창이 열린 동안 사진 소유자가 삭제 후 다른 사진을 올립니다.
select set_config('request.jwt.claim.sub',:'writer',true);
select public.remove_my_avatar();
select public.set_my_avatar('/9gC/9k=');
select set_config('request.jwt.claim.sub',:'reader',true);
select pg_temp.check_report(pg_temp.denied(format('select public.report_avatar(%L,%L,%L,%L)',:'writer',:'original','/9gC/9k=','스팸·광고'),'22023'));
select pg_temp.check_report(pg_temp.denied(format('select public.report_avatar(%L,%L,%L,%L)',:'writer',:'original','/9gB/9k=','기타'),'22023'));
select public.report_avatar(:'writer',:'original','/9gB/9k=','스팸·광고');
select public.report_avatar(:'writer',:'original','/9gB/9k=','스팸·광고');
reset role;
select id as case_id from runspot_private.moderation_cases where avatar_version=:'original' \gset
set local role authenticated;
select pg_temp.check_report(pg_temp.denied(format('select public.moderation_photo(%s)',:case_id),'42501'));
select set_config('request.jwt.claim.sub',:'staff',true);
select pg_temp.check_report(pg_temp.denied(format('select public.moderation_photo(%s)',:case_id),'42501'));
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.check_report(public.moderation_photo(:case_id)='/9gB/9k=');
select public.moderation_decide(:case_id,'warning','신고 원본 확인');
select pg_temp.check_report(public.user_avatar(:'writer')='/9gC/9k=');
-- 현재 버전을 신고한 경우에만 사진이 내려갑니다.
select set_config('request.jwt.claim.sub',:'reader',true);
select public.reportable_avatar(:'writer')->>'version' as newer \gset
select public.report_avatar(:'writer',:'newer','/9gC/9k=','개인정보 노출');
reset role;
select id as new_case from runspot_private.moderation_cases where avatar_version=:'newer' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub',:'staff',true);
select public.moderation_decide(:new_case,'warning','현재 사진 확인');
select pg_temp.check_report(public.user_avatar(:'writer') is null);
select pg_temp.check_report(public.moderation_photo(:new_case)='/9gC/9k=');
rollback;
