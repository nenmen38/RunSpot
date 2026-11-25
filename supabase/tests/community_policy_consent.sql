begin;
insert into auth.users (id) values ('00000000-0000-4000-8000-000000000531');
insert into auth.sessions (id, user_id)
values ('00000000-0000-4000-8000-000000000532', '00000000-0000-4000-8000-000000000531');
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000531', true);
select set_config('request.jwt.claims', '{"session_id":"00000000-0000-4000-8000-000000000532"}', true);

set local role authenticated;
do $$
begin
  if public.my_community_policy_accepted() then
    raise exception '신규 계정에 동의가 먼저 기록되었습니다.';
  end if;
  begin
    perform public.accept_community_policy(0);
    raise exception '다른 버전으로 동의할 수 있습니다.';
  exception when invalid_parameter_value then null;
  end;
end;
$$;
reset role;

do $$
begin
  begin
    insert into runspot_private.board_posts
      (author_id, client_post_id, board, topic, title, body)
    values
      (auth.uid(), gen_random_uuid(), 'national', 'tip', '제목', '본문');
    raise exception '동의 없이 게시물이 작성되었습니다.';
  exception when insufficient_privilege then null;
  end;
end;
$$;

set local role authenticated;
select public.accept_community_policy(1);
select public.accept_community_policy(1);
do $$
begin
  if not public.my_community_policy_accepted() then
    raise exception '운영정책 동의가 저장되지 않았습니다.';
  end if;
end;
$$;
reset role;

insert into runspot_private.board_posts
  (author_id, client_post_id, board, topic, title, body)
values
  (auth.uid(), gen_random_uuid(), 'national', 'tip', '제목', '본문');
rollback;

-- 나머지 기능 테스트는 약관에 이미 동의한 계정으로 검증합니다.
create function auth.accept_community_policy_for_fixture()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into runspot_private.community_policy_consents (user_id, policy_version)
  values (new.id, runspot_private.community_policy_version());
  return new;
end;
$$;
create trigger accept_community_policy_for_fixture after insert on auth.users
for each row execute function auth.accept_community_policy_for_fixture();
