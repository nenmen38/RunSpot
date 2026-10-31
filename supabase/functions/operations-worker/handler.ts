import {
  accessToken,
  type Delivery,
  send,
  type ServiceAccount,
} from "./fcm.ts";

type Config = {
  url: string;
  serviceKey: string;
  workerSecret: string;
  firebase?: ServiceAccount;
};

export function handler(config: Config, request = fetch) {
  const headers = {
    apikey: config.serviceKey,
    Authorization: `Bearer ${config.serviceKey}`,
    "Content-Type": "application/json",
  };
  async function rpc(name: string, body = {}): Promise<unknown> {
    const response = await request(`${config.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error("서버 작업 실패");
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return new Response(null, { status: 405 });
    // 일반 사용자 JWT로는 실행할 수 없으며 별도 서버 전용 비밀을 요구합니다.
    const supplied = req.headers.get("x-worker-secret") ?? "";
    const digest = async (s: string) =>
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
      );
    const [a, b] = await Promise.all([
      digest(supplied),
      digest(config.workerSecret),
    ]);
    let difference = 0;
    for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
    if (config.workerSecret.length < 32 || difference !== 0) {
      return new Response(null, { status: 401 });
    }
    let sent = 0;
    let removed = 0;
    let failed = false;
    // 사진 정리는 Firebase 설정·장애와 독립적으로 계속합니다.
    try {
      const paths = await rpc("claim_unused_board_photos") as string[];
      if (paths.length) {
        const response = await request(
          `${config.url}/storage/v1/object/board-images`,
          {
            method: "DELETE",
            headers,
            body: JSON.stringify({ prefixes: paths }),
            signal: AbortSignal.timeout(20000),
          },
        );
        if (!response.ok) throw new Error("사진 정리 실패");
        removed = paths.length;
      }
    } catch (_) {
      failed = true;
    }
    try {
      if (!config.firebase) throw new Error("푸시 인증 설정이 필요합니다.");
      const token = await accessToken(config.firebase, request);
      const deliveries = await rpc("claim_push_deliveries") as Delivery[];
      // 5개씩 전송하여 함수 실행 시간과 외부 API 부하를 제한합니다.
      for (let i = 0; i < deliveries.length; i += 5) {
        await Promise.all(
          deliveries.slice(i, i + 5).map(async (delivery) => {
            const outcome = await send(
              config.firebase!,
              token,
              delivery,
              request,
            );
            await rpc("finish_push_delivery", {
              job_id: delivery.job_id,
              device_id: delivery.device_id,
              lease: delivery.lease,
              outcome,
            });
            if (outcome === "sent") sent++;
            if (outcome === "retry" || outcome === "failed") failed = true;
          }),
        );
      }
    } catch (_) {
      failed = true;
    }
    // 토큰·개인정보·원본 오류는 응답과 로그에 남기지 않습니다.
    return Response.json({ sent, removed, needs_attention: failed }, {
      status: failed ? 503 : 200,
    });
  };
}
