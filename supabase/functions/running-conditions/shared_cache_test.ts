import { Provider, ProviderFailure, SharedLoader } from "./shared_cache.ts";
import { equal, MemorySharedCache } from "./test_support.ts";

Deno.test("서로 다른 서버 요청도 공동 갱신 한 번의 결과를 사용합니다", async () => {
  const cache = new MemorySharedCache();
  let calls = 0;
  const loader = async (reserve: (provider: Provider) => Promise<void>) => {
    await reserve("air");
    calls++;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return { pm10: 10 };
  };
  const values = await Promise.all(
    Array.from(
      { length: 20 },
      () => new SharedLoader(cache).load("seoul", "latest", 3600, loader),
    ),
  );
  equal(calls, 1);
  equal(cache.attempts.length, 1);
  equal(values.every((value) => value.value.pm10 === 10), true);
});
Deno.test("같은 발표 시각은 재조회하지 않고 다음 발표는 갱신합니다", async () => {
  const cache = new MemorySharedCache(), loader = new SharedLoader(cache);
  let calls = 0;
  const read = async () => ({ value: ++calls });
  await loader.load("weather", "0900", 86400, read);
  cache.now += 600000;
  await loader.load("weather", "0900", 86400, read);
  equal(calls, 1);
  await loader.load("weather", "1000", 86400, read);
  equal(calls, 2);
});
Deno.test("한도 도달 시 외부 호출 없이 마지막 시각과 오류를 보존합니다", async () => {
  const cache = new MemorySharedCache(), loader = new SharedLoader(cache);
  const read = async (reserve: (provider: Provider) => Promise<void>) => {
    await reserve("air");
    return { pm10: 12 };
  };
  await loader.load("dust", "latest", 3600, read);
  const timestamp = cache.entries.get("dust")!.updatedAt;
  cache.now += 3600001;
  cache.allowed = false;
  const result = await loader.load("dust", "latest", 3600, read);
  equal(result.value.pm10, 12);
  equal(result.updatedAt, timestamp);
  equal(result.refreshError, "quota_exhausted");
  equal(cache.attempts.length, 1);
  await loader.load("dust", "latest", 3600, read);
  equal(cache.attempts.length, 1);
});
Deno.test("기관 장애도 예산을 소비하고 재시도 대기 중에는 재조회하지 않습니다", async () => {
  const cache = new MemorySharedCache(), loader = new SharedLoader(cache);
  for (let i = 0; i < 2; i++) {
    try {
      await loader.load("weather", "0900", 86400, async (reserve) => {
        await reserve("kma");
        throw new ProviderFailure("provider_unavailable");
      });
      throw new Error("조회 거절 필요");
    } catch (error) {
      equal((error as Error).message, "provider_unavailable");
    }
  }
  equal(cache.attempts.length, 1);
});
Deno.test("갱신 권한 만료 후 이전 작업자는 새 자료를 덮어쓰지 못합니다", async () => {
  const cache = new MemorySharedCache();
  const first = await cache.claim("weather", "0900");
  cache.now += 180001;
  const next = await cache.claim("weather", "1000");
  equal(
    await cache.reserve("kma", "weather", first.token!),
    "refresh_superseded",
  );
  equal(
    await cache.complete(
      "weather",
      first.token!,
      { temperature: 1 },
      3600,
      null,
    ),
    false,
  );
  equal(
    await cache.complete(
      "weather",
      next.token!,
      { temperature: 20 },
      3600,
      null,
    ),
    true,
  );
  equal((await cache.claim("weather", "1000")).state, "fresh");
});
