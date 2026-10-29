"""격리된 로컬 DB에서 게시글 수정 충돌·도배 차단·게시글과 댓글 신고 중복 처리를 검증합니다."""
import concurrent.futures
import json
import pathlib
import subprocess
import sys
import uuid


def main():
    psql, socket_arg = sys.argv[1:]
    socket = pathlib.Path(socket_arg).resolve()
    if socket.parent != pathlib.Path('/private/tmp') or not socket.name.startswith('runspot-splits-db.'):
        raise ValueError('격리된 임시 로컬 DB에서만 실행할 수 있습니다.')

    def execute(sql, conflict_allowed=False, conflict_code="P0001"):
        result = subprocess.run([psql, '-X', '-h', str(socket), '-p', '55441', '-d', 'postgres',
            '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-At', '-q', '-c', sql],
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            if conflict_allowed and conflict_code in result.stderr:
                return 'conflict'
            raise RuntimeError(result.stderr)
        return result.stdout.strip()

    author, reporter, staff = [str(uuid.uuid4()) for _ in range(3)]
    post_id = str(uuid.uuid4())
    users = ','.join(f"('{item}','{item}@example.com',now())" for item in [author, reporter, staff])

    def authenticated(user, statement):
        return f"""begin; set local lock_timeout='10s'; set local role authenticated;
          set local request.jwt.claim.sub='{user}';
          set local request.jwt.claims='{{"aal":"aal2"}}';
          {statement}; commit;"""

    try:
        execute(f"""insert into auth.users(id,email,email_confirmed_at) values {users};
          update public.profiles set nickname='동시검증'||left(id::text,8) where id in ('{author}','{reporter}','{staff}');
          insert into runspot_private.user_roles(user_id,role) values('{staff}','moderator');
          insert into runspot_private.board_posts(id,author_id,client_post_id,board,topic,title,body)
           values('{post_id}','{author}',gen_random_uuid(),'national','tip','원래 제목','내용');""")
        version = execute(f"select updated_at from runspot_private.board_posts where id='{post_id}'")

        def edit(index):
            return execute(authenticated(author,
                f"select public.update_my_board_post('{post_id}','{version}','tip','수정{index}','내용',null,null,null)"),
                conflict_allowed=True)

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(edit, range(2)))
        assert outcomes.count('conflict') == 1, '같은 편집본의 동시 수정은 한 요청만 반영해야 합니다.'

        # 같은 사용자의 동시 도배 요청도 한 건만 저장해야 합니다.
        def spam(_):
            return execute(f"""insert into runspot_private.board_posts(author_id,client_post_id,board,topic,title,body)
              values('{author}',gen_random_uuid(),'national','tip','중복 검사','동시에 여러 번 등록하는 긴 광고성 게시글 검증 내용입니다.')""",
              conflict_allowed=True, conflict_code='22023')

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(spam, range(2)))
        assert outcomes.count('conflict') == 1, '동시 도배 요청은 한 건만 저장해야 합니다.'

        comment_id = str(uuid.uuid4())
        execute(f"""insert into runspot_private.board_comments(id,post_id,author_id,client_comment_id,body)
          values('{comment_id}','{post_id}','{author}',gen_random_uuid(),'댓글 검증 원문')""")

        def report_comment(_):
            execute(authenticated(reporter, f"select public.report_board_comment('{comment_id}','댓글 신고')"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(report_comment, range(4)))
        result = json.loads(execute(f"select jsonb_build_object('count',count(*),'id',min(id::text)) from runspot_private.board_reports where comment_id='{comment_id}'"))
        assert result['count'] == 1, '동시 댓글 신고가 중복 접수되었습니다.'
        comment_report_id = result['id']

        def resolve_comment(_):
            execute(authenticated(staff, f"select public.resolve_board_report('{comment_report_id}','removed','댓글 검토 후 삭제')"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(resolve_comment, range(2)))
        result = json.loads(execute(f"""select jsonb_build_object(
          'deleted',not exists(select 1 from runspot_private.board_comments where id='{comment_id}'),
          'post_kept',exists(select 1 from runspot_private.board_posts where id='{post_id}'),
          'audit_count',(select count(*) from runspot_private.audit_logs where target_id='{comment_report_id}'))"""))
        assert result == {'deleted': True, 'post_kept': True, 'audit_count': 1}, result

        def report(_):
            execute(authenticated(reporter, f"select public.report_board_post('{post_id}','신고 사유')"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(report, range(4)))
        result = json.loads(execute(f"select jsonb_build_object('count',count(*),'id',min(id::text)) from runspot_private.board_reports where post_id='{post_id}' and comment_id is null"))
        assert result['count'] == 1, '동시 신고가 중복 접수되었습니다.'
        report_id = result['id']

        def resolve(_):
            execute(authenticated(staff, f"select public.resolve_board_report('{report_id}','removed','운영 기준 위반')"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(resolve, range(2)))
        result = json.loads(execute(f"""select jsonb_build_object(
          'deleted',not exists(select 1 from runspot_private.board_posts where id='{post_id}'),
          'audit_count',(select count(*) from runspot_private.audit_logs where target_id='{report_id}'),
          'snapshot',(select snapshot->>'body' from runspot_private.board_reports where id='{report_id}'))"""))
        assert result == {'deleted': True, 'audit_count': 1, 'snapshot': '내용'}, result
        print('동시 수정·도배 차단·게시글 및 댓글 신고·감사 중복 방지 검증 통과')
    finally:
        execute(f"delete from auth.users where id in ('{author}','{reporter}','{staff}')")


if __name__ == '__main__':
    main()
