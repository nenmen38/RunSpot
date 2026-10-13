import { GeminiFeedback, safeSummary, type Summary } from "./gemini.ts";
import { feedbackHandler, type Gateway, type State } from "./handler.ts";
function assert(ok: boolean, message = "검증 실패") {
  if (!ok) throw new Error(message);
}
const summary: Summary = {
  current: { distance_m: 3000, duration_sec: 1200, pace_seconds_per_km: 400 },
  previous: {
    count: 0,
    total_distance_m: 0,
    total_duration_sec: 0,
    average_distance_m: null,
    pace_seconds_per_km: null,
  },
};
const runId = "10000000-0000-0000-0000-000000000081";
const next = "2026-10-16T00:00:00Z";
function request(body: unknown = { run_id: runId }, token = "test") {
  return new Request("https://example.com", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}
function fixture(status = "available") {
  let state: State = { status };
  let calls = 0, reservations = 0, finishes = 0;
  const gateway: Gateway = {
    async authenticate(token) {
      return token === "test" ? "owner" : null;
    },
    async read() {
      return state;
    },
    async reserve(owner, id) {
      assert(owner === "owner" && id === runId);
      if (state.status !== "available") return state;
      reservations++;
      state = { status: "processing", next_available_at: next };
      return {
        status: "reserved",
        request_id: "reservation",
        summary,
        next_available_at: next,
      };
    },
    async finish(_, result) {
      finishes++;
      state = result
        ? {
          status: "ready",
          message: result.message,
          created_at: "2026-10-13T00:00:00Z",
        }
        : { status: "cooldown", next_available_at: next };
    },
  };
  const generator = {
    async generate() {
      calls++;
      return {
        message: "러닝 기록을 남기셨습니다.",
        inputTokens: 200,
        outputTokens: 100,
      };
    },
  };
  return {
    gateway,
    generator,
    counts: () => ({ calls, reservations, finishes }),
  };
}
Deno.test("인증·입력·타인 접근 실패는 AI를 호출하지 않습니다", async () => {
  const f = fixture();
  const handler = feedbackHandler(() => f.gateway, f.generator);
  assert((await handler(request(undefined, "bad"))).status === 401);
  assert(
    (await handler(request({ run_id: runId, email: "private" }))).status ===
      400,
  );
  f.gateway.read = async () => {
    throw new Error("denied");
  };
  assert((await handler(request())).status === 403);
  assert(f.counts().calls === 0);
});
Deno.test("키 미설정과 기존 결과·한도는 예약과 AI 호출이 없습니다", async () => {
  for (
    const status of [
      "available",
      "ready",
      "cooldown",
      "email_required",
      "budget_exhausted",
    ]
  ) {
    const f = fixture(status);
    const response = await feedbackHandler(() => f.gateway, null)(request());
    assert(
      (await response.json()).status ===
        (status === "available" ? "not_configured" : status),
    );
    assert(f.counts().calls === 0 && f.counts().reservations === 0);
  }
});
Deno.test("동시 요청·재조회는 외부 AI 호출이 한 번입니다", async () => {
  const f = fixture();
  const handler = feedbackHandler(() => f.gateway, f.generator);
  await Promise.all(Array.from({ length: 20 }, async () => {
    await (await handler(request())).json();
  }));
  await (await handler(request())).json();
  assert(
    f.counts().calls === 1 && f.counts().reservations === 1 &&
      f.counts().finishes === 1,
  );
});
Deno.test("AI 실패는 자동 재호출하지 않고 실패 상태와 다음 시각을 반환합니다", async () => {
  const f = fixture();
  let calls = 0;
  const handler = feedbackHandler(() => f.gateway, {
    async generate() {
      calls++;
      throw new Error("private provider detail");
    },
  });
  const result = await (await handler(request())).json();
  assert(
    result.status === "generation_failed" && result.next_available_at === next,
  );
  await (await handler(request())).json();
  assert(calls === 1 && f.counts().finishes === 1);
});
Deno.test("Gemini 요청은 숫자 요약만 전송하고 도구·자동 재시도를 사용하지 않습니다", async () => {
  let calls = 0;
  const provider = new GeminiFeedback(
    "secret",
    (async (url, options) => {
      calls++;
      assert(
        String(url).endsWith("gemini-3.5-flash-lite:generateContent") &&
          !String(url).includes("secret"),
      );
      const body = JSON.parse(options!.body as string);
      assert(
        body.generationConfig.maxOutputTokens === 768 &&
          body.generationConfig.candidateCount === 1 && !body.tools,
      );
      const data = JSON.parse(body.contents[0].parts[0].text);
      assert(!data.email && !data.current.latitude && !data.user_id);
      return Response.json({
        candidates: [{
          finishReason: "STOP",
          content: {
            parts: [{
              text: JSON.stringify({ message: "러닝 기록을 남기셨습니다." }),
            }],
          },
        }],
        usageMetadata: {
          promptTokenCount: 200,
          candidatesTokenCount: 80,
          thoughtsTokenCount: 20,
        },
      });
    }) as typeof fetch,
  );
  const input = {
    ...summary,
    email: "private@example.com",
    user_id: "secret-id",
    current: { ...summary.current, latitude: 37 },
  };
  const result = await provider.generate(input);
  assert(
    calls === 1 && result.outputTokens === 100 && result.inputTokens === 200,
  );
});
Deno.test("누락·오염된 숫자 요약은 외부 전송하지 않습니다", () => {
  let rejected = false;
  try {
    safeSummary({
      ...summary,
      current: { ...summary.current, distance_m: NaN },
    });
  } catch {
    rejected = true;
  }
  assert(rejected);
});
Deno.test("Gemini 오류·잘린 응답·HTML·빈 응답·대용량 응답은 저장하지 않습니다", async () => {
  const responses = [
    new Response("private", { status: 429 }),
    Response.json({ candidates: [{ finishReason: "MAX_TOKENS" }] }),
    Response.json({
      candidates: [{
        finishReason: "STOP",
        content: { parts: [{ text: '{"message":"<script>위험</script>"}' }] },
      }],
    }),
    Response.json({ candidates: [] }),
    new Response("x".repeat(32769)),
  ];
  for (const response of responses) {
    let calls = 0, rejected = false;
    const provider = new GeminiFeedback(
      "secret",
      (async () => {
        calls++;
        return response;
      }) as typeof fetch,
    );
    try {
      await provider.generate(summary);
    } catch {
      rejected = true;
    }
    assert(rejected && calls === 1);
  }
});
