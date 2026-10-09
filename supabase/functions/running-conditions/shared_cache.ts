import type { SupabaseClient } from "@supabase/supabase-js";

export type Provider = "kma" | "air" | "stations";
export interface CacheClaim {
  state: "fresh" | "owner" | "busy" | "cooldown";
  token: string | null;
  payload: unknown;
  updatedAt: string | null;
  error: string | null;
}
export interface SharedCache {
  claim(key: string, slot: string): Promise<CacheClaim>;
  reserve(provider: Provider, key: string, token: string): Promise<string>;
  complete(
    key: string,
    token: string,
    payload: unknown,
    ttl: number,
    error: string | null,
  ): Promise<boolean>;
}
export class ProviderFailure extends Error {
  constructor(public code: string) {
    super(code);
  }
}
export class DatabaseSharedCache implements SharedCache {
  constructor(private client: SupabaseClient) {}
  private async rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<unknown> {
    const { data, error } = await this.client.rpc(name, args);
    if (error) throw new ProviderFailure("cache_unavailable");
    return data;
  }
  async claim(key: string, slot: string): Promise<CacheClaim> {
    return await this.rpc("claim_environment_refresh", {
      requested_key: key,
      requested_slot: slot,
    }) as CacheClaim;
  }
  async reserve(
    provider: Provider,
    key: string,
    token: string,
  ): Promise<string> {
    return await this.rpc("reserve_environment_attempt", {
      requested_provider: provider,
      requested_key: key,
      token,
    }) as string;
  }
  async complete(
    key: string,
    token: string,
    payload: unknown,
    ttl: number,
    error: string | null,
  ): Promise<boolean> {
    return await this.rpc("complete_environment_refresh", {
      requested_key: key,
      token,
      cache_payload: payload,
      ttl_seconds: ttl,
      error_code: error,
    }) === true;
  }
}
export interface CachedResult<T> {
  value: T;
  updatedAt: string | null;
  refreshError: string | null;
}
export class SharedLoader {
  constructor(private cache: SharedCache) {}
  async load<T>(
    key: string,
    slot: string,
    ttl: number,
    loader: (reserve: (provider: Provider) => Promise<void>) => Promise<T>,
  ): Promise<CachedResult<T>> {
    let claim = await this.cache.claim(key, slot);
    // 첫 공동 조회는 짧게 결과를 기다리되 외부 요청을 추가하지 않습니다.
    for (
      let i = 0;
      claim.state === "busy" && claim.payload == null && i < 4;
      i++
    ) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      claim = await this.cache.claim(key, slot);
    }
    if (claim.state === "fresh") {
      return {
        value: claim.payload as T,
        updatedAt: claim.updatedAt,
        refreshError: null,
      };
    }
    if (claim.state !== "owner" || !claim.token) {
      return this.previous<T>(
        claim,
        claim.state === "busy"
          ? "refresh_in_progress"
          : claim.error ?? "provider_unavailable",
      );
    }
    const token = claim.token;
    try {
      const value = await loader(async (provider) => {
        const result = await this.cache.reserve(provider, key, token);
        if (result !== "allowed") throw new ProviderFailure(result);
      });
      if (!await this.cache.complete(key, token, value, ttl, null)) {
        throw new ProviderFailure("refresh_superseded");
      }
      return { value, updatedAt: new Date().toISOString(), refreshError: null };
    } catch (failure) {
      const code = failure instanceof ProviderFailure
        ? failure.code
        : "provider_unavailable";
      if (code !== "cache_unavailable") {
        await this.cache.complete(key, token, null, ttl, code);
      }
      return this.previous<T>(claim, code);
    }
  }
  private previous<T>(claim: CacheClaim, code: string): CachedResult<T> {
    if (claim.payload == null) throw new ProviderFailure(code);
    return {
      value: claim.payload as T,
      updatedAt: claim.updatedAt,
      refreshError: code,
    };
  }
}
