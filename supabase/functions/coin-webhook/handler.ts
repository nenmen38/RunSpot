// RevenueCat 결제 알림을 받아 코인을 기록합니다. 앱은 코인을 직접 늘릴 수 없습니다.
type Config = {
  url: string;
  serviceKey: string;
  webhookSecret: string;
};

type RevenueCatEvent = {
  type?: string;
  app_user_id?: string;
  product_id?: string;
  transaction_id?: string;
  purchased_at_ms?: number;
  environment?: string;
  cancel_reason?: string;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function sameSecret(supplied: string, expected: string) {
  const digest = async (s: string) =>
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
    );
  const [a, b] = await Promise.all([digest(supplied), digest(expected)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return expected.length >= 32 && difference === 0;
}

export function handler(config: Config, request = fetch) {
  const headers = {
    apikey: config.serviceKey,
    Authorization: `Bearer ${config.serviceKey}`,
    "Content-Type": "application/json",
  };
  async function rpc(name: string, body: unknown): Promise<unknown> {
    const response = await request(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error("서버 작업 실패");
    return await response.json();
  }
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return new Response(null, { status: 405 });
    // RevenueCat 웹훅 설정의 Authorization 값과 같은 비밀만 받습니다.
    const supplied = (req.headers.get("authorization") ?? "")
      .replace(/^Bearer\s+/i, "");
    if (!await sameSecret(supplied, config.webhookSecret)) {
      return new Response(null, { status: 401 });
    }
    let event: RevenueCatEvent;
    try {
      event = ((await req.json()) as { event?: RevenueCatEvent }).event ?? {};
    } catch (_) {
      return new Response(null, { status: 400 });
    }
    try {
      if (
        event.type === "NON_RENEWING_PURCHASE" &&
        event.product_id?.startsWith("coins_")
      ) {
        // 앱이 RevenueCat에 로그인한 무작위 결제 식별자만 사용자와 연결합니다.
        if (!event.transaction_id || !uuid.test(event.app_user_id ?? "")) {
          return Response.json({ recorded: false });
        }
        const recorded = await rpc("record_coin_purchase", {
          transaction: event.transaction_id,
          customer: event.app_user_id,
          product: event.product_id,
          purchased: event.purchased_at_ms
            ? new Date(event.purchased_at_ms).toISOString()
            : null,
          store_environment: event.environment ?? "PRODUCTION",
        });
        return Response.json({ recorded });
      }
      if (
        event.type === "CANCELLATION" &&
        event.product_id?.startsWith("coins_") && event.transaction_id
      ) {
        // 일회성 상품의 취소 알림은 스토어 환불입니다.
        const refunded = await rpc("refund_coin_purchase", {
          transaction: event.transaction_id,
        });
        return Response.json({ refunded });
      }
    } catch (_) {
      // 실패하면 RevenueCat이 다시 보내도록 서버 오류로 응답합니다.
      return new Response(null, { status: 500 });
    }
    // 테스트 알림과 코인과 무관한 알림은 받기만 합니다.
    return Response.json({ ignored: true });
  };
}
