import { handler } from "./handler.ts";
function assert(value: unknown, message = "검증 실패"): asserts value {
  if (!value) throw new Error(message);
}
const secret = "s".repeat(40);
const customer = "11111111-2222-4333-8444-555555555555";
function setup(status = 200, result: unknown = true) {
  const calls: { name: string; body: Record<string, unknown> }[] = [];
  const request = ((url: string, init: RequestInit) => {
    calls.push({
      name: url.split("/").pop()!,
      body: JSON.parse(init.body as string),
    });
    return Promise.resolve(Response.json(result, { status }));
  }) as typeof fetch;
  const serve = handler(
    { url: "https://db", serviceKey: "service", webhookSecret: secret },
    request,
  );
  const post = (event: Record<string, unknown>, auth = `Bearer ${secret}`) =>
    serve(
      new Request("https://fn", {
        method: "POST",
        headers: { authorization: auth },
        body: JSON.stringify({ event }),
      }),
    );
  return { calls, post };
}

Deno.test("비밀이 다르면 코인을 기록하지 않음", async () => {
  const { calls, post } = setup();
  const response = await post({ type: "NON_RENEWING_PURCHASE" }, "Bearer x");
  assert(response.status === 401);
  assert(calls.length === 0);
});

Deno.test("코인 결제를 거래 식별자와 함께 기록함", async () => {
  const { calls, post } = setup();
  const response = await post({
    type: "NON_RENEWING_PURCHASE",
    app_user_id: customer,
    product_id: "coins_3300",
    transaction_id: "GPA.1",
    purchased_at_ms: 0,
    environment: "SANDBOX",
  });
  assert(response.status === 200);
  assert(calls[0].name === "record_coin_purchase");
  assert(calls[0].body.transaction === "GPA.1");
  assert(calls[0].body.customer === customer);
  assert(calls[0].body.product === "coins_3300");
  assert(calls[0].body.store_environment === "SANDBOX");
});

Deno.test("임시 익명 계정 결제와 다른 상품은 기록하지 않음", async () => {
  const { calls, post } = setup();
  await post({
    type: "NON_RENEWING_PURCHASE",
    app_user_id: "$RCAnonymousID:abc",
    product_id: "coins_1100",
    transaction_id: "GPA.2",
  });
  await post({
    type: "NON_RENEWING_PURCHASE",
    app_user_id: customer,
    product_id: "blue_profile_border",
    transaction_id: "GPA.3",
  });
  await post({ type: "TEST" });
  assert(calls.length === 0);
});

Deno.test("환불 알림은 코인을 회수하고 서버 오류는 재전송을 요청함", async () => {
  const ok = setup();
  await ok.post({
    type: "CANCELLATION",
    product_id: "coins_1100",
    transaction_id: "GPA.4",
  });
  assert(ok.calls[0].name === "refund_coin_purchase");
  assert(ok.calls[0].body.transaction === "GPA.4");
  const broken = setup(500);
  const response = await broken.post({
    type: "NON_RENEWING_PURCHASE",
    app_user_id: customer,
    product_id: "coins_1100",
    transaction_id: "GPA.5",
  });
  assert(response.status === 500);
});
