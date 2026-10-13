// 인증 대역이 있는 전용 임시 PostgreSQL에만 실행합니다.
const socket = Deno.env.get("FEEDBACK_TEST_SOCKET") ?? "";
const psql = Deno.env.get("FEEDBACK_TEST_PSQL") ?? "psql";
if (!socket.startsWith("/private/tmp/runspot-feedback-db.")) {
  throw new Error("격리된 피드백 테스트 DB가 필요합니다.");
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
Deno.test("동시 20개 연결에서 계정별 요청과 전체 마지막 예산을 한 번만 예약합니다", async () => {
  assert(
    await sql(
      "select count(*) from information_schema.columns where table_schema='auth' and table_name='users' and column_name='encrypted_password'",
    ) === "0",
    "실제 Auth DB 실행 차단",
  );
  const uid = (n: number) =>
    `00000000-0000-0000-0000-${String(100 + n).padStart(12, "0")}`;
  const rid = (n: number) =>
    `10000000-0000-0000-0000-${String(100 + n).padStart(12, "0")}`;
  try {
    await sql(
      Array.from(
        { length: 20 },
        (_, i) =>
          `insert into auth.users(id,email,email_confirmed_at) values('${
            uid(i)
          }','race${i}@example.com',now());
      insert into public.runs(id,user_id,client_run_id,started_at,ended_at,distance_m,duration_sec)
      values('${rid(i)}','${
            uid(i)
          }',gen_random_uuid(),now()-interval '1 hour',now()-interval '30 minutes',1000,600);`,
      )
        .join("\n"),
    );
    const accountResults = await Promise.all(
      Array.from(
        { length: 20 },
        () =>
          sql(`select public.reserve_run_feedback('${uid(0)}','${rid(0)}')`),
      ),
    );
    assert(
      accountResults.map((value) => JSON.parse(value)).filter((r) =>
        r.status === "reserved"
      )
        .length === 1,
      "계정별 예약은 한 번이어야 합니다.",
    );
    await sql(
      "update runspot_private.feedback_limits set daily_calls=2,monthly_calls=1000",
    );
    const budgetResults = await Promise.all(
      Array.from({ length: 19 }, (_, i) =>
        sql(
          `select public.reserve_run_feedback('${uid(i + 1)}','${rid(i + 1)}')`,
        )),
    );
    assert(
      budgetResults.map((value) => JSON.parse(value)).filter((r) =>
        r.status === "reserved"
      )
        .length === 1,
      "남은 전체 예산은 한 회만 허용해야 합니다.",
    );
    assert(
      await sql("select count(*) from runspot_private.feedback_requests") ===
        "2",
      "동시 요청도 상한을 초과하지 않아야 합니다.",
    );
  } finally {
    await sql(
      "delete from runspot_private.feedback_requests; delete from auth.users where email like 'race%@example.com'; update runspot_private.feedback_limits set daily_calls=100,monthly_calls=1000",
    );
  }
});
