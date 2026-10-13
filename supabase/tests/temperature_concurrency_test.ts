// 인증 대역이 있는 전용 임시 PostgreSQL에서만 실행합니다.
const socket = Deno.env.get("TEMPERATURE_TEST_SOCKET") ?? "";
const psql = Deno.env.get("TEMPERATURE_TEST_PSQL") ?? "psql";
if (!socket.startsWith("/private/tmp/runspot-temperature-db.")) {
  throw new Error("격리된 기온 테스트 DB가 필요합니다.");
}
async function sql(query: string): Promise<string> {
  const result = await new Deno.Command(psql, {
    args: [
      "-h",
      socket,
      "-p",
      "55439",
      "-d",
      "postgres",
      "-At",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      query,
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return new TextDecoder().decode(result.stdout).trim();
}
function assert(ok: boolean, message: string) {
  if (!ok) throw new Error(message);
}
Deno.test("동시 저장은 기온·경로를 한 번 확정하고 변경된 재시도는 차단합니다", async () => {
  assert(
    await sql(
      "select count(*) from information_schema.columns where table_schema='auth' and table_name='users' and column_name='encrypted_password'",
    ) === "0",
    "실제 Auth DB 실행 차단",
  );
  const owner = "00000000-0000-0000-0000-000000000088";
  const client = "10000000-0000-0000-0000-000000000088";
  const save = (temp: number) =>
    `begin; set local role authenticated;
    select set_config('request.jwt.claim.sub','${owner}',true);
    select public.save_my_run_with_temperature('${client}','2026-10-12T00:00:00Z',
      '2026-10-12T01:00:00Z',100,60,'[[[37,127]]]',${temp},'2026-10-12T00:30:00Z'); commit;`;
  try {
    await sql(`insert into auth.users(id) values('${owner}')`);
    const results = await Promise.all(
      Array.from({ length: 20 }, () => sql(save(23.5))),
    );
    assert(results.length === 20, "동일한 동시 재시도 성공");
    assert(
      await sql(`select count(*) from public.runs where user_id='${owner}'`) ===
        "1",
      "한 건만 저장",
    );
    const changed = await Promise.allSettled(
      Array.from({ length: 10 }, () => sql(save(24))),
    );
    assert(
      changed.every((r) => r.status === "rejected"),
      "다른 기온 재시도 모두 거절",
    );
    assert(
      await sql(
        `select temperature_c from public.runs where user_id='${owner}'`,
      ) === "23.5",
      "최초 기온 유지",
    );
    assert(
      await sql(
        `select count(*) from runspot_private.measured_run_routes t join public.runs r on r.id=t.run_id where r.user_id='${owner}'`,
      ) === "1",
      "경로도 한 건만 저장",
    );
  } finally {
    await sql(`delete from auth.users where id='${owner}'`);
  }
});
