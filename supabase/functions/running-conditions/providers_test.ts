import {
  baseTime,
  coordinate,
  dust,
  grid,
  kstTime,
  number,
  Providers,
  stationRegion,
  supported,
  weather,
} from "./providers.ts";
import { MemorySharedCache } from "./test_support.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `결과 불일치: ${JSON.stringify(actual)} / ${JSON.stringify(expected)}`,
    );
  }
}
Deno.test("공식 기상 격자 원점과 서울 좌표를 변환합니다", () => {
  equal(grid([38, 126]), [43, 136]);
  equal(grid([37.5665, 126.978]), [60, 127]);
  equal(grid([35.1796, 129.0756]), [98, 76]);
});
Deno.test("공급 시각과 한국 시각의 자정 경계를 처리합니다", () => {
  equal(baseTime(new Date("2026-10-08T15:05:00Z")), {
    date: "20261008",
    time: "2300",
  });
  equal(baseTime(new Date("2026-10-08T15:12:00Z")), {
    date: "20261009",
    time: "0000",
  });
  equal(kstTime("2026-10-09 24:00"), "2026-10-09T15:00:00.000Z");
  equal(kstTime("20261009 0900"), "2026-10-09T00:00:00.000Z");
  equal(kstTime("2026-10-09 25:00"), null);
  equal(kstTime("2026-02-30 09:00"), null);
});
Deno.test("결측값과 센서 점검 자료를 정상 농도로 바꾸지 않습니다", () => {
  equal(number(null, 0, 100), null);
  equal(number("", 0, 100), null);
  equal(number("-", 0, 100), null);
  equal(number("0", 0, 100), 0);
  equal(
    dust({
      dataTime: "2026-10-09 09:00",
      pm10Value: "10",
      pm10Flag: "점검중",
      pm25Value: "-",
    }),
    { observedAt: "2026-10-09T00:00:00.000Z", pm10: null, pm25: null },
  );
  equal(
    weather([{
      baseDate: "20261009",
      baseTime: "0900",
      category: "T1H",
      obsrValue: "-999",
    }]).temperature,
    null,
  );
});
Deno.test("좌표는 약 1km로 반올림하며 국내 범위만 지원합니다", () => {
  equal(coordinate({ latitude: 37.5665123, longitude: 126.978123 }), [
    37.57,
    126.98,
  ]);
  equal(supported([37.57, 126.98]), true);
  equal(supported([37.77, -122.4]), false);
  for (
    const body of [
      { latitude: "37", longitude: 127 },
      { latitude: NaN, longitude: 127 },
      { latitude: 91, longitude: 127 },
      null,
    ]
  ) {
    let failed = false;
    try {
      coordinate(body);
    } catch {
      failed = true;
    }
    equal(failed, true);
  }
});
Deno.test("가까운 측정소를 선택하고 관측값만 공유 캐시합니다", async () => {
  const cache = new MemorySharedCache();
  const requests: URL[] = [];
  const mock = ((input: URL) => {
    requests.push(input);
    const items = input.pathname.endsWith("getMsrstnList")
      ? [
        {
          stationName: "먼 측정소",
          dmX: 35,
          dmY: 127,
          item: "PM10,PM2.5",
          addr: "전북 전주시",
        },
        {
          stationName: "가까운 측정소",
          dmX: 37.57,
          dmY: 126.98,
          item: "PM10,PM2.5",
          addr: "서울특별시 중구",
        },
      ]
      : [{
        stationName: "가까운 측정소",
        dataTime: "2026-10-09 09:00",
        pm10Value: "20",
        pm25Value: "10",
      }];
    return Promise.resolve(
      Response.json({
        response: {
          header: { resultCode: "00" },
          body: { items, totalCount: items.length },
        },
      }),
    );
  }) as unknown as typeof fetch;
  const providers = new Providers(
    cache,
    { kma: "시험용", air: "시험용" },
    mock,
  );
  equal((await providers.getDust([37.57, 126.98])).station, "가까운 측정소");
  await providers.getDust([37.571, 126.981]);
  equal(requests.length, 2);
  equal(requests[1].searchParams.get("sidoName"), "서울");
  equal(requests[1].searchParams.has("latitude"), false);
  equal([...cache.entries.keys()], ["stations:v2", "dust:v2:서울"]);
  equal(cache.attempts, ["stations", "air"]);
});
Deno.test("거부된 API는 인증키나 요청 URL을 오류로 반환하지 않습니다", async () => {
  const cache = new MemorySharedCache();
  const providers = new Providers(
    cache,
    { kma: "노출되면안되는키", air: "노출되면안되는키" },
    (() =>
      Promise.resolve(new Response("거부", { status: 403 }))) as typeof fetch,
  );
  try {
    await providers.getDust([37.57, 126.98]);
    throw new Error("거부 실패");
  } catch (error) {
    equal((error as Error).message, "permission_denied");
  }
});

Deno.test("공식 시도 명칭과 개편된 전남광주를 공동 조회 구역으로 변환합니다", () => {
  equal(stationRegion("강원특별자치도 춘천시"), "강원");
  equal(stationRegion("전북특별자치도 전주시"), "전북");
  equal(stationRegion("광주광역시 북구"), "전남광주");
  equal(stationRegion("전라남도 목포시"), "전남광주");
  equal(stationRegion("알 수 없는 주소"), null);
});

Deno.test("같은 시도 안의 서로 다른 측정소도 한 번 받은 자료를 공유합니다", async () => {
  const cache = new MemorySharedCache();
  let calls = 0;
  const mock = ((input: URL) => {
    calls++;
    const items = input.pathname.endsWith("getMsrstnList")
      ? [
        {
          stationName: "첫 측정소",
          dmX: 37.57,
          dmY: 126.98,
          item: "PM10,PM2.5",
          addr: "서울 중구",
        },
        {
          stationName: "다음 측정소",
          dmX: 37.62,
          dmY: 127.02,
          item: "PM10,PM2.5",
          addr: "서울 성북구",
        },
      ]
      : [
        {
          stationName: "첫 측정소",
          dataTime: "2026-10-10 09:00",
          pm10Value: "20",
          pm25Value: "10",
        },
        {
          stationName: "다음 측정소",
          dataTime: "2026-10-10 09:00",
          pm10Value: "80",
          pm25Value: "35",
        },
      ];
    return Promise.resolve(
      Response.json({
        response: {
          header: { resultCode: "00" },
          body: { items, totalCount: items.length },
        },
      }),
    );
  }) as unknown as typeof fetch;
  const providers = new Providers(cache, { kma: "시험", air: "시험" }, mock);
  equal((await providers.getDust([37.57, 126.98])).pm10, 20);
  equal((await providers.getDust([37.62, 127.02])).pm10, 80);
  equal(calls, 2);
  equal(cache.attempts, ["stations", "air"]);
});

Deno.test("추가 페이지는 별도로 예약하고 한도에 걸린 부분 목록은 저장하지 않습니다", async () => {
  const cache = new MemorySharedCache();
  let calls = 0;
  const mock = ((input: URL) => {
    calls++;
    const station = {
      stationName: "첫 측정소",
      dmX: 37.57,
      dmY: 126.98,
      item: "PM10,PM2.5",
      addr: "서울 중구",
    };
    const catalog = input.pathname.endsWith("getMsrstnList");
    const items = catalog ? [station] : [{
      stationName: "첫 측정소",
      dataTime: "2026-10-10 09:00",
      pm10Value: "20",
      pm25Value: "10",
    }];
    if (!catalog) cache.allowed = false;
    return Promise.resolve(
      Response.json({
        response: {
          header: { resultCode: "00" },
          body: { items, totalCount: catalog ? 1 : 2 },
        },
      }),
    );
  }) as unknown as typeof fetch;
  const providers = new Providers(cache, { kma: "시험", air: "시험" }, mock);
  try {
    await providers.getDust([37.57, 126.98]);
    throw new Error("부분 목록 거절 필요");
  } catch (error) {
    equal((error as Error).message, "quota_exhausted");
  }
  equal(cache.entries.get("dust:v2:서울")!.payload, null);
  equal(calls, 2);
  equal(cache.attempts, ["stations", "air"]);
});

Deno.test("예산 저장소 장애는 외부 요청 없이 실패합니다", async () => {
  const cache = new MemorySharedCache();
  cache.reserve = () => Promise.reject(new Error("저장소 연결 오류"));
  let calls = 0;
  const providers = new Providers(
    cache,
    { kma: "시험", air: "시험" },
    (() => {
      calls++;
      return Promise.resolve(Response.json({}));
    }) as typeof fetch,
  );
  try {
    await providers.getWeather(
      [37.57, 126.98],
      new Date("2026-10-10T00:12:00Z"),
    );
    throw new Error("조회 거절 필요");
  } catch (error) {
    equal((error as Error).message, "provider_unavailable");
  }
  equal(calls, 0);
});
