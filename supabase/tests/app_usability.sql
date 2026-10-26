\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000401','usability401@example.com',now()),
 ('00000000-0000-0000-0000-000000000402','usability402@example.com',now()),
 ('00000000-0000-0000-0000-000000000403','usability403@example.com',now());
update public.profiles set nickname='개선'||right(id::text,3) where id::text like '%00000000040_';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000403','moderator');
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
 values('00000000-0000-0000-0000-000000000401',gen_random_uuid(),now()-interval '1 hour',now(),2000,600) returning id as run_id \gset
insert into public.runs(user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
 values('00000000-0000-0000-0000-000000000401',gen_random_uuid(),now()-interval '1 hour',now(),0,10),
 ('00000000-0000-0000-0000-000000000401',gen_random_uuid(),now()-interval '1 hour',now(),600,60);
select xp as original_xp from runspot_private.run_rewards where run_id=:'run_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000401',true);
select pg_temp.assert_true(not public.can_access_management(),'일반 계정 관리 메뉴 숨김');
select pg_temp.assert_true((public.my_run_statistics()->>'completed_runs')::integer=1,'0km와 검토 보류 횟수 제외');
select public.set_my_run_hidden(:'run_id',true);
select pg_temp.assert_true((public.my_run_statistics()->>'completed_runs')::integer=1,'숨김 후 완료 횟수 보존');
select pg_temp.assert_true((public.my_run_reward(:'run_id')->>'xp')::integer=:'original_xp','숨김 후 보상 보존');
select pg_temp.assert_true((select hidden from public.runs where id=:'run_id'),'본인 기록 숨김');
select public.set_my_run_hidden(:'run_id',false);
select pg_temp.assert_true((select not hidden from public.runs where id=:'run_id'),'본인 기록 복원');
select pg_temp.assert_true(pg_temp.fails('update public.runs set hidden=true','42501'),'직접 숨김 변경 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000402',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.set_my_run_hidden(%L,true)',:'run_id'),'42501'),'타인 기록 숨김 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000403',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
select pg_temp.assert_true(public.can_access_management(),'관리자 메뉴는 다중 인증 전에도 표시');
select pg_temp.assert_true(pg_temp.fails('select public.board_report_cases()','42501'),'메뉴 접근과 관리 권한 분리');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000401',true);
select public.create_board_post(gen_random_uuid(),'national','원래 제목','원래 내용','tip',null,null,null) as post_id \gset
reset role;
select updated_at as version from runspot_private.board_posts where id=:'post_id' \gset
set local role authenticated;
select public.update_my_board_post(:'post_id',:'version','course','수정 제목','수정 내용',null,null,null);
-- 응답 유실 뒤 동일 내용 재시도는 중복 수정 없이 성공합니다.
select public.update_my_board_post(:'post_id',:'version','course','수정 제목','수정 내용',null,null,null);
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,%L,''course'',''다른 제목'',''다른 내용'',null,null,null)',:'post_id',:'version'),'P0001'),'오래된 편집본 덮어쓰기 차단');
select pg_temp.assert_true(pg_temp.fails(format('select public.report_board_post(%L,''본인 신고'')',:'post_id'),'22023'),'본인 신고 차단');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000402',true);
select pg_temp.assert_true(pg_temp.fails(format('select public.update_my_board_post(%L,%L,''course'',''타인 수정'',''내용'',null,null,null)',:'post_id',:'version'),'42501'),'타인 게시글 수정 차단');
select public.report_board_post(:'post_id','부적절한 내용');
select public.report_board_post(:'post_id','중복 신고');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_reports','42501'),'신고 원본 조회 차단');
reset role;
select pg_temp.assert_true((select count(*)=1 from runspot_private.board_reports where post_id=:'post_id'),'중복 신고 방지');
select id as report_id from runspot_private.board_reports where post_id=:'post_id' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000403',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true((public.board_report_cases()->0->>'title')='수정 제목','신고 당시 수정 내용 보존');
select public.resolve_board_report(:'report_id','removed','운영 기준 위반 확인');
select public.resolve_board_report(:'report_id','removed','중복 처리');
select pg_temp.assert_true(pg_temp.fails(format('select public.resolve_board_report(%L,''dismissed'',''결정 변경'')',:'report_id'),'P0001'),'처리 결과 덮어쓰기 차단');
reset role;
select pg_temp.assert_true(not exists(select 1 from runspot_private.board_posts where id=:'post_id'),'관리자 신고 처리로 게시글 삭제');
select pg_temp.assert_true((select snapshot->>'body'='수정 내용' and status='removed' from runspot_private.board_reports where id=:'report_id'),'삭제 후 신고 근거 보존');
select pg_temp.assert_true((select count(*)=1 from runspot_private.audit_logs where target_id=:'report_id'),'처리 감사 중복 방지');
rollback;
\echo '기록 숨김·통계·관리 메뉴·게시글 수정·신고 권한 검증 통과'
