// 인증 대역이 있는 격리된 임시 PostgreSQL에서만 실행합니다.
const socket = Deno.env.get("ENVIRONMENT_TEST_SOCKET") ?? "";
const psql = Deno.env.get("ENVIRONMENT_TEST_PSQL") ?? "psql";
if (!socket.startsWith("/private/tmp/runspot-environment-db.")) {
  throw new Error("격리된 환경 조회 테스트 DB 소켓이 필요합니다.");
}
async function sql(query: string): Promise<string> {
  const command = new Deno.Command(psql, {
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
  });
  const result = await command.output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return new TextDecoder().decode(result.stdout).trim();
}
function assert(ok: boolean, message: string) {
  if (!ok) throw new Error(message);
}
Deno.test("20개 DB 연결에서도 공동 갱신은 하나이며 450회 상한을 넘지 않습니다", async () => {
  assert(
    await sql(
      "select count(*) from information_schema.columns where table_schema='auth' and table_name='users' and column_name='email'",
    ) === "0",
    "실제 Auth DB에는 실행할 수 없습니다.",
  );
  try {
    const claims = await Promise.all(
      Array.from(
        { length: 20 },
        () =>
          sql("select public.claim_environment_refresh('race:test','hour')"),
      ),
    );
    assert(
      claims.map((claim) => JSON.parse(claim)).filter((claim) =>
        claim.state === "owner"
      ).length === 1,
      "지역 갱신 담당자는 하나여야 합니다.",
    );
    await sql(
      "insert into runspot_private.environment_attempts(provider) select 'air' from generate_series(1,449)",
    );
    const leases = await Promise.all(
      Array.from(
        { length: 20 },
        (_, i) =>
          sql(`select public.claim_environment_refresh('race:${i}','hour')`),
      ),
    );
    const results = await Promise.all(
      leases.map((lease, i) =>
        sql(
          `select public.reserve_environment_attempt('air','race:${i}','${
            JSON.parse(lease).token
          }')`,
        )
      ),
    );
    assert(
      results.filter((result) => result === "allowed").length === 1,
      "남은 한 회만 원자적으로 허용해야 합니다.",
    );
    assert(
      await sql(
        "select count(*) from runspot_private.environment_attempts where provider='air'",
      ) === "450",
      "기관 상한 450회 초과 금지",
    );
  } finally {
    await sql(
      "delete from runspot_private.environment_attempts where provider='air'; delete from runspot_private.environment_shared_cache where cache_key like 'race:%'",
    );
  }
});
