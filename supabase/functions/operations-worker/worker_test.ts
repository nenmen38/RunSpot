import { type Delivery, payload, send } from "./fcm.ts";
import { handler } from "./handler.ts";
function assert(value: unknown, message = "검증 실패"): asserts value {
  if (!value) throw new Error(message);
}
const delivery: Delivery = {
  job_id: "작업",
  device_id: "기기",
  lease: "임대",
  token: "비밀토큰",
  recipient_id: "본인",
  kind: "board_comment",
  target_id: "게시글",
};
const account = {
  project_id: "프로젝트",
  client_email: "계정",
  private_key: "비밀",
};
Deno.test("잠금 화면 알림은 본문과 개인정보를 포함하지 않음", () => {
  const value = payload(delivery);
  assert(
    value.message.notification.body === "내 글이나 댓글에 새 댓글이 달렸어요.",
  );
  assert(!("nickname" in value.message.data));
  assert(value.message.android.notification.tag === delivery.job_id);
});
Deno.test("기기 등록 해제만 토큰을 폐기하고 설정 오류와 일시 장애는 구분함", async () => {
  const response = (status: number, code: string) =>
    (() =>
      Promise.resolve(
        Response.json({ error: { details: [{ errorCode: code }] } }, {
          status,
        }),
      )) as typeof fetch;
  assert(
    await send(account, "인증", delivery, response(404, "UNREGISTERED")) ===
      "invalid",
  );
  assert(
    await send(account, "인증", delivery, response(400, "INVALID_ARGUMENT")) ===
      "failed",
  );
  assert(
    await send(account, "인증", delivery, response(503, "UNAVAILABLE")) ===
      "retry",
  );
  assert(
    await send(
      account,
      "인증",
      delivery,
      response(403, "PERMISSION_DENIED"),
    ) === "retry",
  );
});
Deno.test("일반 사용자와 잘못된 작업 비밀은 외부 요청 전에 거부함", async () => {
  let calls = 0;
  const worker = handler(
    {
      url: "https://example.com",
      serviceKey: "서버키",
      workerSecret: "a".repeat(40),
    },
    (() => {
      calls++;
      throw new Error("호출 금지");
    }) as typeof fetch,
  );
  assert(
    (await worker(new Request("https://example.com", { method: "POST" })))
      .status === 401,
  );
  assert(calls === 0);
});
Deno.test("푸시 설정이 없어도 사진은 저장소 API로 제거하며 경로를 응답에 노출하지 않음", async () => {
  const calls: string[] = [];
  const worker = handler(
    {
      url: "https://example.com",
      serviceKey: "서버키",
      workerSecret: "a".repeat(40),
    },
    (async (url, init) => {
      calls.push(String(url));
      if (String(url).endsWith("claim_unused_board_photos")) {
        return Response
          .json(["개인경로.jpg"]);
      }
      assert(init?.method === "DELETE");
      assert(String(init?.body).includes("개인경로.jpg"));
      return Response.json([]);
    }) as typeof fetch,
  );
  const response = await worker(
    new Request("https://example.com", {
      method: "POST",
      headers: { "x-worker-secret": "a".repeat(40) },
    }),
  );
  const result = await response.json();
  assert(response.status === 503 && result.removed === 1);
  assert(calls[1].endsWith("/storage/v1/object/board-images"));
  assert(!JSON.stringify(result).includes("개인경로"));
});

Deno.test("인증 후 발송에 성공하면 같은 임대로 완료를 기록함", async () => {
  const keys = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const privateKey = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...der))
  }\n-----END PRIVATE KEY-----`;
  let finished = false;
  const worker = handler(
    {
      url: "https://example.com",
      serviceKey: "서버키",
      workerSecret: "a".repeat(40),
      firebase: { ...account, private_key: privateKey },
    },
    (async (url, init) => {
      const path = String(url);
      if (path.endsWith("claim_unused_board_photos")) return Response.json([]);
      if (path === "https://oauth2.googleapis.com/token") {
        return Response.json(
          { access_token: "인증토큰" },
        );
      }
      if (path.endsWith("claim_push_deliveries")) {
        return Response.json([
          delivery,
        ]);
      }
      if (path.endsWith("messages:send")) {
        assert(
          (init?.headers as Record<string, string>).Authorization ===
            "Bearer 인증토큰",
        );
        return Response.json({ name: "발송결과" });
      }
      assert(path.endsWith("finish_push_delivery"));
      const completion = JSON.parse(String(init?.body));
      assert(
        completion.lease === delivery.lease && completion.outcome === "sent",
      );
      finished = true;
      return Response.json(null);
    }) as typeof fetch,
  );
  const result = await worker(
    new Request("https://example.com", {
      method: "POST",
      headers: { "x-worker-secret": "a".repeat(40) },
    }),
  );
  assert(result.status === 200 && finished);
  assert((await result.json()).sent === 1);
});
