import { handler } from "./handler.ts";

Deno.serve(handler({
  url: Deno.env.get("SUPABASE_URL")!,
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  environment: Deno.env.get("COIN_STORE_ENVIRONMENT") === "SANDBOX"
    ? "SANDBOX"
    : "PRODUCTION",
  webhookSecret: Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "",
}));
