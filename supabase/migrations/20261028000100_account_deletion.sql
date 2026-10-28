-- 앱 안에서 본인 계정을 삭제합니다. 프로필·기록·게시글 등 연결된 자료는 외래 키 연쇄 삭제로 함께 지워집니다.
-- 게시판 사진 파일은 Storage API로 지워야 하므로 앱이 이 함수를 부르기 전에 본인 폴더를 비웁니다.
create function runspot_private.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
  -- 정지된 계정도 탈퇴할 수 있도록 활성 상태는 확인하지 않습니다.
  if viewer is null or not exists(select 1 from auth.users where id=viewer) then
    raise exception '로그인 상태를 확인해 주세요.' using errcode='42501';
  end if;
  -- 관리자 역할 회수와 같은 순서로 잠가 처리 중인 관리 작업과 엇갈리지 않게 합니다.
  perform 1 from runspot_private.user_roles where user_id=viewer for update;
  perform 1 from runspot_private.account_controls where user_id=viewer for update;
  insert into runspot_private.audit_logs(actor_id,action,target_id) values(null,'account_delete',viewer);
  delete from auth.users where id=viewer;
end;
$$;
create function public.delete_my_account() returns void language sql security invoker set search_path = ''
as $$ select runspot_private.delete_my_account(); $$;
revoke all on function runspot_private.delete_my_account(),public.delete_my_account() from public,anon,authenticated;
grant execute on function runspot_private.delete_my_account(),public.delete_my_account() to authenticated;
notify pgrst,'reload schema';
