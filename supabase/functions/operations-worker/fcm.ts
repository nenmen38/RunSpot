export type Delivery = {
  job_id: string;
  device_id: string;
  lease: string;
  token: string;
  recipient_id: string;
  kind: string;
  target_id: string;
  /** 서버가 만든 알림 제목·내용(보낸 사람 이름·메시지)입니다. 수신자가 내용 표시를 끄면 일반 문구가 옵니다. */
  title?: string;
  body?: string;
};
export type Outcome = "sent" | "retry" | "invalid" | "failed";
export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};
const encode = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value)).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
const bytes = (value: string) => new TextEncoder().encode(value);

export async function accessToken(
  account: ServiceAccount,
  request = fetch,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = encode(bytes(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = encode(
    bytes(
      JSON.stringify({
        iss: account.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    bytes(`${header}.${claim}`),
  );
  const response = await request("https://oauth2.googleapis.com/token", {
    method: "POST",
    signal: AbortSignal.timeout(10000),
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${encode(new Uint8Array(signature))}`,
    }),
  });
  if (!response.ok) throw new Error("푸시 인증 실패");
  const result = await response.json();
  if (typeof result.access_token !== "string") {
    throw new Error("푸시 인증 응답 오류");
  }
  return result.access_token;
}

export function payload(delivery: Delivery) {
  const body = ({
    friend_request: "새 친구 요청이 도착했어요.",
    group_invite: "함께 달리기 초대가 도착했어요.",
    board_comment: "내 글이나 댓글에 새 댓글이 달렸어요.",
    friend_message: "친구에게서 새 메시지가 도착했어요.",
    room_message: "단체 대화방에 새 메시지가 도착했어요.",
    board_like: "내 글에 좋아요가 달렸어요.",
    crew_invite: "크루 초대가 도착했어요.",
    comeback: "러너가 기다리고 있어요. 오늘 가볍게 달려 볼까요?",
  } as Record<string, string>)[delivery.kind];
  // 친구 메시지는 보낸 친구별로 알림 하나에 덮어써서 연달아 와도 쌓이지 않게 합니다.
  const group = delivery.kind === "friend_message"
    ? `chat-${delivery.target_id}`
    : delivery.kind === "room_message"
    ? `room-${delivery.target_id}`
    : delivery.job_id;
  if (!body) throw new Error("지원하지 않는 알림");
  // 휴대폰 알림 글자 수를 제한하고 줄바꿈은 한 칸으로 바꿉니다.
  const clean = (value: string | undefined, limit: number) => {
    const text = value?.replace(/\s+/g, " ").trim();
    return text ? [...text].slice(0, limit).join("") : undefined;
  };
  return {
    message: {
      token: delivery.token,
      notification: {
        title: clean(delivery.title, 40) ?? "뜀터",
        body: clean(delivery.body, 120) ?? body,
      },
      data: {
        kind: delivery.kind,
        target_id: delivery.target_id,
        recipient_id: delivery.recipient_id,
        event_id: delivery.job_id,
      },
      android: {
        ttl: "900s",
        collapse_key: group,
        notification: { tag: group },
      },
      apns: {
        headers: {
          "apns-collapse-id": group,
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 900),
        },
        payload: { aps: { sound: "default" } },
      },
    },
  };
}

export async function send(
  account: ServiceAccount,
  token: string,
  delivery: Delivery,
  request = fetch,
): Promise<Outcome> {
  try {
    const response = await request(
      `https://fcm.googleapis.com/v1/projects/${
        encodeURIComponent(account.project_id)
      }/messages:send`,
      {
        method: "POST",
        signal: AbortSignal.timeout(10000),
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload(delivery)),
      },
    );
    if (response.ok) return "sent";
    const error = await response.json().catch(() => ({}));
    // INVALID_ARGUMENT에는 설정 오류도 있으므로 UNREGISTERED만 토큰 폐기로 처리합니다.
    if (
      error.error?.details?.some((detail: { errorCode?: string }) =>
        detail.errorCode === "UNREGISTERED"
      )
    ) return "invalid";
    if ([401, 403, 429].includes(response.status) || response.status >= 500) {
      return "retry";
    }
    return "failed";
  } catch (_) {
    return "retry";
  }
}
