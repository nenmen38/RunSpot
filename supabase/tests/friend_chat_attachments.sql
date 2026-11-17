\set ON_ERROR_STOP on
begin;

create function pg_temp.check_attachments(ok boolean, message text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception '%',message; end if;
end;
$$;
create function pg_temp.denied(statement text, expected text default '42501') returns boolean language plpgsql as $$
begin execute statement; return false; exception when others then return sqlstate=expected; end;
$$;

\set alice '00000000-0000-0000-0000-000000000291'
\set bob '00000000-0000-0000-0000-000000000292'
\set third '00000000-0000-0000-0000-000000000293'
\set run '00000000-0000-0000-0000-000000000294'
\set photo_request '00000000-0000-0000-0000-000000000295'
\set run_request '00000000-0000-0000-0000-000000000296'
\set jpeg '/9j/2Q=='

insert into auth.users(id,email,email_confirmed_at) values
  (:'alice','attachments291@example.com',now()),(:'bob','attachments292@example.com',now()),
  (:'third','attachments293@example.com',now());
update public.profiles set nickname='첨부검증'||right(id::text,3),visibility='friends'
  where id in (:'alice',:'bob',:'third');
insert into public.friendships(user_low,user_high,requested_by,status) values
  (:'alice',:'bob',:'alice','accepted'),(:'alice',:'third',:'alice','accepted');
insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
values(:'run',:'alice',:'run',now()-interval '30 min',now(),5000,1500);

set local role authenticated;
select set_config('request.jwt.claim.sub',:'alice',true);
select public.friend_chat_send_content(:'bob',null,:'photo_request',null,:'jpeg',null);
select public.friend_chat_send_content(:'bob',null,:'photo_request',null,:'jpeg',null);
select public.friend_chat_read(:'bob')->0->>'id' as photo_id \gset
select pg_temp.check_attachments(jsonb_array_length(public.friend_chat_read(:'bob'))=1,'사진 재시도는 한 번만 저장');
select pg_temp.check_attachments(pg_temp.denied(format(
  'select public.friend_chat_send_content(%L,%L,%L,%s,null,null)',:'third','다른 채팅 답장',:'run_request',:photo_id),'22023'),'다른 대화의 메시지에 답장할 수 없음');
select public.friend_chat_send_content(:'bob',null,:'run_request',:photo_id,null,:'run');
select pg_temp.check_attachments(
  public.friend_chat_read(:'bob')->0->'run_summary'='{"distance_m":5000,"duration_sec":1500}'::jsonb,
  '달리기 공유에는 거리와 시간만 포함');
select pg_temp.check_attachments(public.friend_chat_read(:'bob')->0->>'reply_preview'='사진','답장 미리보기');
select pg_temp.check_attachments(not ((public.friend_chat_read(:'bob')->1) ? 'photo'),'목록에서 사진 바이트 제외');

select set_config('request.jwt.claim.sub',:'third',true);
select pg_temp.check_attachments(public.friend_chat_photo(:'alice',:photo_id) is null,'다른 친구의 사진 조회 차단');
select pg_temp.check_attachments(pg_temp.denied(format(
  'select public.friend_chat_send_content(%L,null,%L,null,null,%L)',:'alice',:'run_request',:'run')),
  '다른 사용자의 기록 공유 차단');

select set_config('request.jwt.claim.sub',:'bob',true);
select pg_temp.check_attachments(public.friend_chat_photo(:'alice',:photo_id)=:'jpeg','대화 참여자의 사진 조회');
select pg_temp.check_attachments(pg_temp.denied(format(
  'select public.friend_chat_delete(%L,%s)',:'alice',:photo_id)),'받은 메시지 삭제 차단');
select pg_temp.check_attachments(public.friend_chat_unread_total()=2,'사진과 기록이 안 읽은 개수에 포함');

select set_config('request.jwt.claim.sub',:'alice',true);
select public.friend_chat_delete(:'bob',:photo_id);
select public.friend_chat_delete(:'bob',:photo_id);
select public.friend_chat_send_content(:'bob',null,:'photo_request',null,:'jpeg',null);
select set_config('request.jwt.claim.sub',:'bob',true);
select pg_temp.check_attachments(public.friend_chat_photo(:'alice',:photo_id) is null,'삭제한 사진 조회 차단');
select pg_temp.check_attachments(public.friend_chat_read(:'alice')->0->>'reply_preview'='삭제된 메시지입니다.','삭제한 원문을 답장에서도 숨김');
select pg_temp.check_attachments(public.friend_chat_read(:'alice')->1->>'kind'='deleted','삭제 후 재시도해도 복구되지 않음');
select pg_temp.check_attachments(public.friend_chat_unread_total()=1,'삭제 메시지를 안 읽은 개수에서 제외');

select public.change_my_block(:'alice',true);
select pg_temp.check_attachments(pg_temp.denied(format(
  'select public.friend_chat_read(%L)',:'alice')),'차단 후 대화 읽기 금지');

reset role;
set local role anon;
select pg_temp.check_attachments(pg_temp.denied(format(
  'select public.friend_chat_photo(%L,%s)',:'alice',:photo_id)),'익명 사진 조회 차단');
rollback;
