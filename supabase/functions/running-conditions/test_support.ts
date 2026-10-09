import {
  CacheClaim,
  Provider,
  ProviderFailure,
  SharedCache,
  SharedLoader,
} from "./shared_cache.ts";

export function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `결과 불일치: ${JSON.stringify(actual)} / ${JSON.stringify(expected)}`,
    );
  }
}
type Entry = CacheClaim & {
  slot: string;
  freshUntil: number;
  leaseUntil: number;
  retryAfter: number;
};
export class MemorySharedCache implements SharedCache {
  entries = new Map<string, Entry>();
  attempts: Provider[] = [];
  now = Date.parse("2026-10-10T00:00:00Z");
  allowed = true;
  async claim(key: string, slot: string): Promise<CacheClaim> {
    let entry = this.entries.get(key);
    if (!entry) {
      entry = {
        state: "owner",
        slot,
        token: null,
        payload: null,
        updatedAt: null,
        error: null,
        freshUntil: 0,
        leaseUntil: 0,
        retryAfter: 0,
      };
      this.entries.set(key, entry);
    }
    let state: CacheClaim["state"];
    if (
      entry.slot === slot && entry.payload != null &&
      entry.freshUntil > this.now
    ) state = "fresh";
    else if (entry.leaseUntil > this.now) state = "busy";
    else if (entry.retryAfter > this.now) state = "cooldown";
    else {
      state = "owner";
      entry.token = crypto.randomUUID();
      entry.slot = slot;
      entry.freshUntil = 0;
      entry.leaseUntil = this.now + 180000;
    }
    return {
      state,
      token: state === "owner" ? entry.token : null,
      payload: entry.payload,
      updatedAt: entry.updatedAt,
      error: entry.error,
    };
  }
  async reserve(
    provider: Provider,
    key: string,
    token: string,
  ): Promise<string> {
    const entry = this.entries.get(key);
    if (entry?.token !== token || entry.leaseUntil <= this.now) {
      return "refresh_superseded";
    }
    if (!this.allowed) return "quota_exhausted";
    this.attempts.push(provider);
    return "allowed";
  }
  async complete(
    key: string,
    token: string,
    payload: unknown,
    ttl: number,
    error: string | null,
  ): Promise<boolean> {
    const entry = this.entries.get(key);
    if (entry?.token !== token || entry.leaseUntil <= this.now) return false;
    if (!error) {
      entry.payload = payload;
      entry.updatedAt = new Date(this.now).toISOString();
    }
    entry.error = error;
    entry.token = null;
    entry.leaseUntil = 0;
    entry.retryAfter = error ? this.now + 300000 : 0;
    entry.freshUntil = error ? 0 : this.now + ttl * 1000;
    return true;
  }
}
