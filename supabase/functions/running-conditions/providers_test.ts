import {
  baseTime,
  Cache,
  coordinate,
  dust,
  grid,
  kstTime,
  number,
  Providers,
  supported,
  weather,
} from "./providers.ts";

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
  const stored = new Map<string, unknown>();
  const cache: Cache = {
    read: (key) => Promise.resolve(stored.get(key)),
    write: (key, value) => {
      stored.set(key, value);
      return Promise.resolve();
    },
  };
  const requests: URL[] = [];
  const mock = ((input: URL) => {
    requests.push(input);
    const items = input.pathname.endsWith("getMsrstnList")
      ? [
        { stationName: "먼 측정소", dmX: 35, dmY: 127, item: "PM10,PM2.5" },
        {
          stationName: "가까운 측정소",
          dmX: 37.57,
          dmY: 126.98,
          item: "PM10,PM2.5",
        },
      ]
      : [{ dataTime: "2026-10-09 09:00", pm10Value: "20", pm25Value: "10" }];
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
  equal(requests[1].searchParams.get("stationName"), "가까운 측정소");
  equal(requests[1].searchParams.has("latitude"), false);
  equal([...stored.keys()], ["stations:v1", "dust:가까운 측정소"]);
});
Deno.test("거부된 API는 인증키나 요청 URL을 오류로 반환하지 않습니다", async () => {
  const cache: Cache = {
    read: () => Promise.resolve(null),
    write: () => Promise.resolve(),
  };
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
