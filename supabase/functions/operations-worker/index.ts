import { handler } from "./handler.ts";
import type { ServiceAccount } from "./fcm.ts";

let firebase: ServiceAccount | undefined;
try {
  firebase = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "null") ??
    undefined;
} catch (_) {
  // 잘못된 설정 내용은 로그에 출력하지 않고 작업 상태로만 알립니다.
}
Deno.serve(handler({
  url: Deno.env.get("SUPABASE_URL")!,
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  workerSecret: Deno.env.get("OPERATIONS_WORKER_SECRET") ?? "",
  firebase,
}));
