import { createClient } from "@supabase/supabase-js";
import {
  Cache,
  coordinate,
  ProviderFailure,
  Providers,
  supported,
} from "./providers.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
Deno.serve(async (request: Request) => {
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
    const url = Deno.env.get("SUPABASE_URL")!,
      anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const options = {
      auth: { persistSession: false, autoRefreshToken: false },
    };
    const client = createClient(url, anon, {
      ...options,
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await client.auth.getUser(authorization.slice(7));
    if (error || !data.user) return reply({ error: "unauthorized" }, 401);
    const reader = request.body?.getReader();
    if (!reader) return reply({ error: "invalid_location" }, 400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.length;
      if (size > 256) {
        await reader.cancel();
        return reply({ error: "invalid_location" }, 400);
      }
      chunks.push(chunk.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    const text = new TextDecoder().decode(bytes);
    let location: [number, number];
    try {
      location = coordinate(JSON.parse(text));
    } catch {
      return reply({ error: "invalid_location" }, 400);
    }
    const quota = await client.rpc("consume_environment_request");
    if (quota.error) return reply({ error: "forbidden" }, 403);
    if (!quota.data) return reply({ error: "rate_limited" }, 429);
    if (!supported(location)) return reply({ error: "unsupported_area" }, 422);
    const admin = createClient(
      url,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      options,
    );
    const cache: Cache = {
      async read(key) {
        const result = await admin.rpc("read_environment_cache", {
          requested_key: key,
        });
        if (result.error) throw new ProviderFailure("cache_unavailable");
        return result.data;
      },
      async write(key, value, ttl) {
        const result = await admin.rpc("write_environment_cache", {
          requested_key: key,
          cache_payload: value,
          ttl_seconds: ttl,
        });
        if (result.error) throw new ProviderFailure("cache_unavailable");
      },
    };
    const providers = new Providers(cache, {
      kma: Deno.env.get("KMA_SERVICE_KEY") ?? "",
      air: Deno.env.get("AIRKOREA_SERVICE_KEY") ?? "",
    });
    const now = new Date();
    // 부분 장애가 발생해도 다른 기관의 정상 관측값은 그대로 제공합니다.
    const results = await Promise.allSettled([
      providers.getWeather(location, now),
      providers.getDust(location),
    ]);
    const errors: Record<string, string> = {};
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      if (result.status === "rejected") {
        errors[i === 0 ? "weather" : "dust"] =
          result.reason instanceof ProviderFailure
            ? result.reason.code
            : "provider_unavailable";
      }
    }
    return reply({
      fetchedAt: now.toISOString(),
      weather: results[0].status === "fulfilled" ? results[0].value : null,
      dust: results[1].status === "fulfilled" ? results[1].value : null,
      errors,
    });
  } catch {
    return reply({ error: "unavailable" }, 503);
  }
});
