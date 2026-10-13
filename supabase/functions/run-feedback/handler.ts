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
      let body: { run_id?: string };
      try {
        body = await boundedJson(
          new Response(request.body),
          128,
        ) as typeof body;
      } catch {
        return reply({ error: "invalid_request" }, 400);
      }
      if (
        !body || typeof body.run_id !== "string" ||
        !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.run_id) ||
        Object.keys(body).length !== 1
      ) {
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
        const result = await generator.generate(reservation.summary);
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
