"""격리된 로컬 인증 대역 DB에서 승인 중복·일일 한도의 동시 처리를 검증합니다."""
import concurrent.futures
import json
import pathlib
import subprocess
import sys
import uuid


def main():
    psql, socket = sys.argv[1:]
    socket = pathlib.Path(socket).resolve()
    if socket.parent != pathlib.Path('/private/tmp') or not socket.name.startswith('runspot-splits-db.'):
        raise ValueError('격리된 임시 로컬 DB에서만 실행할 수 있습니다.')

    def execute(sql):
        result = subprocess.run([psql, '-X', '-h', str(socket), '-p', '55441', '-d', 'postgres',
                                 '-v', 'ON_ERROR_STOP=1', '-At', '-q', '-c', sql],
                                check=True, capture_output=True, text=True, timeout=30)
        return result.stdout.strip()

    first, second, staff = [str(uuid.uuid4()) for _ in range(3)]
    runs = [str(uuid.uuid4()) for _ in range(4)]
    users = ','.join(f"('{item}')" for item in [first, second, staff])
    try:
        execute(f"""begin;
          insert into auth.users(id) values {users};
          insert into runspot_private.user_roles(user_id,role) values('{staff}','moderator');
          insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec) values
            ('{runs[0]}','{first}',gen_random_uuid(),now()-interval '1 hour',now(),2000,200),
            ('{runs[1]}','{second}',gen_random_uuid(),now()-interval '4 hours',now(),30000,10000),
            ('{runs[2]}','{second}',gen_random_uuid(),now()-interval '3 hours',now(),40000,3600),
            ('{runs[3]}','{second}',gen_random_uuid(),now()-interval '3 hours',now(),40000,3600);
          commit;""")
        cases = json.loads(execute(f"""select jsonb_object_agg(run_id,id)
          from runspot_private.integrity_cases where run_id in ('{runs[0]}','{runs[2]}','{runs[3]}');"""))

        def approve(case_id):
            execute(f"""begin; set local lock_timeout='10s';
              set local role authenticated;
              set local request.jwt.claim.sub='{staff}';
              set local request.jwt.claims='{{"aal":"aal2"}}';
              select public.resolve_review('{case_id}','approved','동시 승인 검증'); commit;""")

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(approve, [cases[runs[0]]] * 4))
            list(pool.map(approve, [cases[runs[2]], cases[runs[3]]]))
        result = json.loads(execute(f"""select jsonb_build_object(
          'single_xp',(select sum(xp) from runspot_private.run_rewards where user_id='{first}'),
          'single_audit',(select count(*) from runspot_private.integrity_actions where case_id='{cases[runs[0]]}'),
          'daily_xp',(select sum(xp) from runspot_private.run_rewards where user_id='{second}'),
          'approved_xp',(select jsonb_agg(xp order by xp) from runspot_private.run_rewards
            where run_id in ('{runs[2]}','{runs[3]}')));"""))
        assert result == {'single_xp': 30, 'single_audit': 1, 'daily_xp': 500, 'approved_xp': [0, 200]}, result
        print('동시 승인 중복 지급 및 일일 500 XP 한도 검증 통과')
    finally:
        execute(f"delete from auth.users where id in ('{first}','{second}','{staff}');")


if __name__ == '__main__':
    main()
