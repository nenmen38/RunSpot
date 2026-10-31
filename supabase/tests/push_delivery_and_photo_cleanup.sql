\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.fails(statement text,expected_code text) returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected_code; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000901','push901@example.com',now()),
 ('00000000-0000-0000-0000-000000000902','push902@example.com',now());
update public.profiles set nickname='푸시검증'||right(id::text,3),visibility='public' where id::text like '%00000000090_';
insert into auth.sessions(id,user_id) values
 ('00000000-0000-0000-0000-000000000911','00000000-0000-0000-0000-000000000901'),
 ('00000000-0000-0000-0000-000000000912','00000000-0000-0000-0000-000000000902');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000902',true);
select set_config('request.jwt.claims','{"session_id":"00000000-0000-0000-0000-000000000911"}',true);
select pg_temp.assert_true(pg_temp.fails('select public.register_push_device(repeat(''t'',40),''android'')','42501'),'다른 계정의 세션으로 기기 등록 거부');
select set_config('request.jwt.claims','{"session_id":"00000000-0000-0000-0000-000000000912"}',true);
select public.register_push_device(repeat('t',40),'android');
select pg_temp.assert_true((public.my_push_preferences()->>'friend_request')::boolean,'수신 설정 기본값');
select pg_temp.assert_true(pg_temp.fails('select public.claim_push_deliveries()','42501'),'앱에서 토큰 발송 목록 조회 거부');
select pg_temp.assert_true(pg_temp.fails('select public.claim_unused_board_photos()','42501'),'앱에서 사진 정리 거부');
reset role;
insert into public.friendships(user_low,user_high,requested_by) values
 ('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902','00000000-0000-0000-0000-000000000901');
set local role service_role;
select public.claim_push_deliveries() as claimed \gset
select pg_temp.assert_true(jsonb_array_length(:'claimed'::jsonb)=1,'친구 요청을 기기별로 발송');
select pg_temp.assert_true(jsonb_array_length(public.claim_push_deliveries())=0,'진행 중 임대의 중복 발송 방지');
select public.finish_push_delivery((:'claimed'::jsonb->0->>'job_id')::uuid,(:'claimed'::jsonb->0->>'device_id')::uuid,gen_random_uuid(),'sent');
reset role;
select pg_temp.assert_true((select not done from runspot_private.push_deliveries limit 1),'오래되거나 다른 임대로 결과 변경 거부');
set local role service_role;
select public.finish_push_delivery((:'claimed'::jsonb->0->>'job_id')::uuid,(:'claimed'::jsonb->0->>'device_id')::uuid,(:'claimed'::jsonb->0->>'lease')::uuid,'sent');
select pg_temp.assert_true(jsonb_array_length(public.claim_push_deliveries())=0,'완료 발송 재실행 방지');
reset role;
-- 수신 거부와 차단은 이미 만들어진 작업에도 즉시 적용합니다.
update runspot_private.push_deliveries set done=false,available_at=now();
set local role authenticated;
select public.my_push_preferences(friend_request=>false);
set local role service_role;
select pg_temp.assert_true(jsonb_array_length(public.claim_push_deliveries())=0,'수신 거부 후 발송하지 않음');
set local role authenticated;
select public.my_push_preferences(friend_request=>true);
reset role;
insert into runspot_private.blocks(blocker_id,blocked_id) values('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902');
set local role service_role;
select pg_temp.assert_true(jsonb_array_length(public.claim_push_deliveries())=0,'차단 후 발송하지 않음');
reset role;
delete from runspot_private.blocks;
set local role authenticated;
select public.unregister_push_device();
reset role;
select pg_temp.assert_true((select count(*)=0 from runspot_private.push_devices),'로그아웃 기기 연결 해제');

-- 실제 사용 중·신고 보존·최근 업로드를 제외하고 오래된 미사용 파일만 격리합니다.
insert into storage.objects(bucket_id,name,created_at) values
 ('board-images','00000000-0000-0000-0000-000000000901/11111111-1111-4111-8111-111111111111.jpg',now()-interval '2 days'),
 ('board-images','00000000-0000-0000-0000-000000000901/22222222-2222-4222-8222-222222222222.jpg',now()-interval '2 days'),
 ('board-images','00000000-0000-0000-0000-000000000901/33333333-3333-4333-8333-333333333333.jpg',now());
insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body,image_paths)
 values('00000000-0000-0000-0000-000000000901',gen_random_uuid(),'national','tip','사진 검증','보관 사진',
 array['00000000-0000-0000-0000-000000000901/11111111-1111-4111-8111-111111111111.jpg']);
set local role service_role;
select public.claim_unused_board_photos() as paths \gset
select pg_temp.assert_true(jsonb_array_length(:'paths'::jsonb)=1 and :'paths'::jsonb->>0 like '%22222222-2222-4222-8222-222222222222.jpg','미사용 오래된 사진만 격리');
reset role;
select pg_temp.assert_true(pg_temp.fails($q$update runspot_private.board_posts set image_paths=array['00000000-0000-0000-0000-000000000901/22222222-2222-4222-8222-222222222222.jpg']$q$,'22023'),'삭제 진행 중인 사진 재첨부 거부');
select pg_temp.assert_true((select count(*)=3 from storage.objects),'SQL은 파일 메타데이터를 직접 삭제하지 않음');
insert into runspot_private.board_reports(post_id,reporter_id,author_id,snapshot,reason)
 select id,'00000000-0000-0000-0000-000000000902',author_id,jsonb_build_object('images',to_jsonb(image_paths)),'신고 보존' from runspot_private.board_posts;
delete from runspot_private.board_posts;
set local role service_role;
select pg_temp.assert_true(jsonb_array_length(public.claim_unused_board_photos())=1,'삭제된 글의 신고 증거 사진 보존');
rollback;
