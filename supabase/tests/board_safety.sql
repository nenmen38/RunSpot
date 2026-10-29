\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected; end; $$;
select pg_temp.assert_true(runspot_private.board_text_violation('씨발')='profanity','명확한 욕설');
select pg_temp.assert_true(runspot_private.board_text_violation('씨 . 1 발')='profanity','기호·공백·숫자 우회');
select pg_temp.assert_true(runspot_private.board_text_violation('씨'||chr(8203)||'발')='profanity','보이지 않는 문자 우회');
select pg_temp.assert_true(runspot_private.board_text_violation('ｆｕｃｋ')='profanity','호환 문자 정규화');
select pg_temp.assert_true(runspot_private.board_text_violation('신발 추천, 시발점과 시발역, 씨앗 발아, 병신년 역사, 18km 달리기') is null,'정상 단어 부분 일치 방지');
select pg_temp.assert_true(runspot_private.board_text_violation('ㅅㅂ 초성 퀴즈') is null,'모호한 초성 자동 차단 제외');
select pg_temp.assert_true(runspot_private.board_text_violation(repeat('https://example.com ',6))='link_spam','과도한 링크');
select pg_temp.assert_true(runspot_private.board_text_violation(repeat('https://example.com ',5)) is null,'허용 링크 개수');
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000951','safety951@example.com',now()),
 ('00000000-0000-0000-0000-000000000952','safety952@example.com',now()),
 ('00000000-0000-0000-0000-000000000953','safety953@example.com',now());
update public.profiles set nickname='안전검증'||right(id::text,3) where id::text like '%00000000095_';
insert into runspot_private.user_roles(user_id,role) values('00000000-0000-0000-0000-000000000953','admin');
insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,title,body) values
 ('00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'national','tip','안전한 게시글','주말 러닝 코스를 공유합니다.');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body) values
 ('00000000-0000-0000-0000-00000000c951','00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'검토할 댓글');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body,parent_id) values
 ('00000000-0000-0000-0000-00000000c952','00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'검토할 답글','00000000-0000-0000-0000-00000000c951');
select pg_temp.assert_true(pg_temp.fails($q$update runspot_private.board_posts set body='씨발' where id='00000000-0000-0000-0000-00000000a951'$q$,'22023'),'게시글 수정도 검사');
select pg_temp.assert_true(pg_temp.fails($q$update runspot_private.board_comments set body='개새끼' where id='00000000-0000-0000-0000-00000000c951'$q$,'22023'),'댓글 수정도 검사');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000952',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.create_board_post(gen_random_uuid(),'national','씨발','내용','tip')$q$,'22023'),'직접 작성 RPC 우회 차단');
select pg_temp.assert_true(pg_temp.fails($q$select public.create_board_comment(gen_random_uuid(),'00000000-0000-0000-0000-00000000a951','씨발','00000000-0000-0000-0000-00000000c951')$q$,'22023'),'답글 작성 검사');
select public.report_board_comment('00000000-0000-0000-0000-00000000c951','욕설·비방');
select public.report_board_comment('00000000-0000-0000-0000-00000000c951','중복 접수');
select public.report_board_comment('00000000-0000-0000-0000-00000000c952','스팸·광고');
select public.report_board_post('00000000-0000-0000-0000-00000000a951','게시글 신고');
select pg_temp.assert_true(pg_temp.fails('select * from runspot_private.board_reports','42501'),'신고 원본 비공개');
select pg_temp.assert_true(pg_temp.fails('select public.board_report_cases()','42501'),'일반 사용자 관리 목록 거부');
select pg_temp.assert_true(pg_temp.fails($q$select public.report_board_comment('00000000-0000-0000-0000-00000000c951',' ')$q$,'22023'),'빈 사유 거부');
reset role;
select pg_temp.assert_true((select count(*)=3 from runspot_private.board_reports),'중복 신고 방지 및 댓글·게시글 신고 독립');
select pg_temp.assert_true((select snapshot->>'body'='검토할 댓글' from runspot_private.board_reports where comment_id='00000000-0000-0000-0000-00000000c951'),'신고 당시 댓글 보존');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body,parent_id) values
 ('00000000-0000-0000-0000-00000000c955','00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'추가 검토','00000000-0000-0000-0000-00000000c951');
insert into runspot_private.board_reports(post_id,reporter_id,author_id,snapshot,reason)
 select gen_random_uuid(),'00000000-0000-0000-0000-000000000952','00000000-0000-0000-0000-000000000951','{"limit_test":true}'::jsonb,'한도 검증' from generate_series(1,17);
set local role authenticated;
select public.report_board_comment('00000000-0000-0000-0000-00000000c951','한도에서도 중복 재시도');
select pg_temp.assert_true(pg_temp.fails($q$select public.report_board_comment('00000000-0000-0000-0000-00000000c955','새 신고')$q$,'P0001'),'게시글·댓글 합산 신고 한도');
reset role;
delete from runspot_private.board_reports where snapshot->>'limit_test'='true';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000951',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.report_board_comment('00000000-0000-0000-0000-00000000c951','본인 신고')$q$,'22023'),'본인 댓글 신고 거부');
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values('00000000-0000-0000-0000-000000000951','00000000-0000-0000-0000-000000000952');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000952',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.report_board_comment('00000000-0000-0000-0000-00000000c951','차단 계정')$q$,'P0001'),'차단된 댓글 신고 거부');
reset role;
delete from runspot_private.blocks where blocker_id='00000000-0000-0000-0000-000000000951';

-- 게시글과 댓글의 원본, 신고 자료에 대한 쓰기 권한은 여전히 공개하지 않습니다.
select pg_temp.assert_true(not has_table_privilege('authenticated','runspot_private.board_reports','insert'),'원본 신고 변조 거부');
select pg_temp.assert_true(not has_function_privilege('authenticated','runspot_private.check_board_safety()','execute'),'검사 함수 직접 호출 거부');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000953',true);
select pg_temp.assert_true(pg_temp.fails('select public.board_report_cases()','42501'),'관리자도 다중 인증 필요');
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
select pg_temp.assert_true(jsonb_array_length(public.board_report_cases())=3,'통합 관리 목록');
select public.resolve_board_report((select (r->>'id')::uuid from jsonb_array_elements(public.board_report_cases()) r where r->>'kind'='comment' and r->>'body'='검토할 댓글'),'removed','검토 후 삭제');
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.board_comments),'원댓글 삭제 시 답글도 삭제');
select pg_temp.assert_true((select count(*)=1 from runspot_private.board_posts),'댓글 처리로 게시글은 삭제하지 않음');
select pg_temp.assert_true((select count(*)=2 from runspot_private.board_reports where comment_id is not null and status='removed'),'연관 댓글 신고 동시 종결');
select pg_temp.assert_true((select count(*)=1 from runspot_private.audit_logs where action='board_report_removed' and actor_id='00000000-0000-0000-0000-000000000953'),'관리 처리 감사 이력');

-- 차단된 원댓글의 답글을 통한 우회 신고와 본인 콘텐츠의 관리자 처리를 차단합니다.
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body) values
 ('00000000-0000-0000-0000-00000000c953','00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000953',gen_random_uuid(),'관리자 본인 댓글');
insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body,parent_id) values
 ('00000000-0000-0000-0000-00000000c954','00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'부모가 차단된 답글','00000000-0000-0000-0000-00000000c953');
insert into runspot_private.blocks(blocker_id,blocked_id) values('00000000-0000-0000-0000-000000000953','00000000-0000-0000-0000-000000000952');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000952',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.report_board_comment('00000000-0000-0000-0000-00000000c954','답글 우회')$q$,'42501'),'차단된 원댓글 아래 답글 신고 거부');
reset role;
delete from runspot_private.blocks where blocker_id='00000000-0000-0000-0000-000000000953';
set local role authenticated;
select public.report_board_comment('00000000-0000-0000-0000-00000000c953','관리자 댓글 신고');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000953',true);
select pg_temp.assert_true(pg_temp.fails($q$select public.resolve_board_report((select (r->>'id')::uuid from jsonb_array_elements(public.board_report_cases()) r where r->>'body'='관리자 본인 댓글'),'removed','본인 처리')$q$,'42501'),'관리자 본인 댓글 신고 처리 거부');
reset role;

-- 정상적인 긴 글과 짧은 응원은 허용하되 같은 사용자의 긴 도배 글은 차단합니다.
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body) values
 ('00000000-0000-0000-0000-000000000951',gen_random_uuid(),'national','tip','도배 검사','같은 내용을 여러 게시판에 반복해서 등록하는 내용입니다.');
select pg_temp.assert_true(pg_temp.fails($q$insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body) values('00000000-0000-0000-0000-000000000951',gen_random_uuid(),'national','tip','다른 제목','같은 내용을 여러 게시판에 반복해서 등록하는 내용입니다.')$q$,'22023'),'반복 도배 거부');
insert into runspot_private.board_comments(post_id,author_id,client_comment_id,body) values
 ('00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'응원합니다!'),
 ('00000000-0000-0000-0000-00000000a951','00000000-0000-0000-0000-000000000951',gen_random_uuid(),'응원합니다!');
rollback;
