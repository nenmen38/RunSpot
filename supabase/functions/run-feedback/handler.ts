import { type HeartSummary, safeHeartSummary } from "./heart_summary.ts";
import { boundedJson, type Feedback, type Summary } from "./gemini.ts";
export type State = {
  status: string;
  message?: string;
  created_at?: string;
  next_available_at?: string;
  request_id?: string;
  summary?: Summary;
};
export interface Gateway {
  authenticate(token: string): Promise<string | null>;
  read(runId: string): Promise<State>;
  reserve(ownerId: string, runId: string): Promise<State>;
  finish(requestId: string, result: Feedback | null): Promise<void>;
}
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
export function feedbackHandler(
  createGateway: (authorization: string) => Gateway,
  generator: { generate(summary: Summary): Promise<Feedback> } | null,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405);
    }
    const authorization = request.headers.get("Authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) {
      return reply({ error: "unauthorized" }, 401);
    }
    try {
      const gateway = createGateway(authorization);
      const owner = await gateway.authenticate(authorization.slice(7));
      if (!owner) return reply({ error: "unauthorized" }, 401);
      let body: { run_id?: string; heart_summary?: unknown };
      let heartSummary: HeartSummary | undefined;
      try {
        body = await boundedJson(
          new Response(request.body),
          131072,
        ) as typeof body;
      } catch {
        return reply({ error: "invalid_request" }, 400);
      }
      if (
        !body || typeof body.run_id !== "string" ||
        !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.run_id) ||
        Object.keys(body).some((key) =>
          !["run_id", "heart_summary"].includes(key)
        )
      ) {
        return reply({ error: "invalid_request" }, 400);
      }
      try {
        if ("heart_summary" in body) {
          heartSummary = safeHeartSummary(body.heart_summary);
        }
      } catch {
        return reply({ error: "invalid_request" }, 400);
      }
      let state: State;
      try {
        state = await gateway.read(body.run_id);
      } catch {
        return reply({ error: "forbidden" }, 403);
      }
      if (state.status !== "available") return reply(state);
      if (!generator) return reply({ status: "not_configured" });
      const reservation = await gateway.reserve(owner, body.run_id);
      if (reservation.status !== "reserved") return reply(reservation);
      if (!reservation.request_id || !reservation.summary) {
        throw new Error("invalid_reservation");
      }
      try {
        const result = await generator.generate({
          ...reservation.summary,
          // 동의된 요약은 이번 생성에만 사용하고 별도 저장하지 않습니다.
          ...(heartSummary === undefined
            ? {}
            : { heart_summary: heartSummary }),
        });
        await gateway.finish(reservation.request_id, result);
      } catch {
        // 실패 후 다시 호출하지 않고 예약과 예산을 유지합니다.
        await gateway.finish(reservation.request_id, null).catch(() => {});
        return reply({
          status: "generation_failed",
          next_available_at: reservation.next_available_at,
        });
      }
      return reply(await gateway.read(body.run_id));
    } catch {
      return reply({ error: "unavailable" }, 503);
    }
  };
}
