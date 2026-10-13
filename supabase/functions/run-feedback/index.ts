import { createClient } from "@supabase/supabase-js";
import { GeminiFeedback } from "./gemini.ts";
import { feedbackHandler, type Gateway, type State } from "./handler.ts";
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const key = Deno.env.get("GEMINI_API_KEY")?.trim();
Deno.serve(feedbackHandler((authorization): Gateway => {
  const url = Deno.env.get("SUPABASE_URL")!;
  const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    ...options,
    global: { headers: { Authorization: authorization } },
  });
  const admin = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    options,
  );
  return {
    async authenticate(token) {
      const { data, error } = await client.auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    async read(runId) {
      const { data, error } = await client.rpc("my_run_feedback", {
        requested_run_id: runId,
      });
      if (error) throw error;
      return data as State;
    },
    async reserve(ownerId, runId) {
      const { data, error } = await admin.rpc("reserve_run_feedback", {
        owner_id: ownerId,
        target_run: runId,
      });
      if (error) throw error;
      return data as State;
    },
    async finish(requestId, result) {
      const { error } = await admin.rpc("finish_run_feedback", {
        request_id: requestId,
        feedback_message: result?.message ?? null,
        input_count: result?.inputTokens ?? 0,
        output_count: result?.outputTokens ?? 0,
      });
      if (error) throw error;
    },
  };
}, key ? new GeminiFeedback(key) : null));
