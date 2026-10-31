import { buildRunContext, safeRunContext } from "./run_context.ts";
import { safeHeartSummary } from "./heart_summary.ts";
import { GeminiFeedback, type Summary } from "./gemini.ts";
function assert(value: boolean) {
  if (!value) throw new Error("검증 실패");
}
const raw = {
  started_at: "2026-11-01T00:00:00Z",
  ended_at: "2026-11-01T00:11:00Z",
  temperature_c: 25,
  temperature_observed_at: "2026-11-01T00:00:00Z",
  split_data: [{ distance_m: 1000, duration_us: 300000000 }, {
    distance_m: 1000,
    duration_us: 330000000,
  }],
  analysis_data: {
    windows: [[0, 300000, 0, 300000], [360000, 690000, 300000, 630000]],
    pauses: [[300000, 360000, 0]],
    elevation: [[0, 500, 2, 4], [500, 1500, 30, 4]],
    gps: [[1, 50, 0, 0, 0, 250, 10, 50], [2, 50, 5, 1, 12000, 500, 30, 50]],
  },
};
Deno.test("감속 구간·고도 차이·관측 거리·GPS 품질·정지 시간을 정확히 요약합니다", () => {
  const result = buildRunContext(raw);
  assert(result.temperature_c === 25 && result.user_pause_sec === 60);
  assert(
    result.segments[0].ascent_m === 15 &&
      result.segments[0].elevation_observed_distance_m === 1000,
  );
  assert(
    result.segments[1].ascent_m === 15 &&
      result.segments[1].elevation_observed_distance_m === 500,
  );
  assert(result.segments[1].previous_segment_difference_sec === 30);
  assert(
    result.segments[1].gps_accuracy_mean_m === 10 &&
      result.segments[1].gps_gap_sec === 12,
  );
});
Deno.test("기존 기록의 없는 자료·오래된 기온은 0으로 대신하지 않습니다", () => {
  const result = buildRunContext({
    ...raw,
    analysis_data: null,
    temperature_observed_at: "2026-10-30T00:00:00Z",
  });
  assert(result.temperature_c === null && result.user_pause_sec === null);
  assert(
    result.segments[0].ascent_m === null &&
      result.segments[0].gps_received === null,
  );
});
Deno.test("짧은 마지막 구간을 완전한 1km 구간과 직접 비교하지 않습니다", () => {
  const result = buildRunContext({
    ...raw,
    split_data: [...raw.split_data, { distance_m: 20, duration_us: 30000000 }],
  });
  assert(
    result.segments[2].previous_segment_difference_sec === null &&
      result.segments[2].pace_seconds_per_km === null,
  );
});
Deno.test("긴 러닝은 감속 구간과 이웃을 포함한 최대 12개 구간만 외부에 보냅니다", () => {
  const result = buildRunContext({
    ...raw,
    analysis_data: null,
    split_data: Array.from(
      { length: 1001 },
      (_, i) => ({ distance_m: 1000, duration_us: (300 + i) * 1e6 }),
    ),
  });
  assert(result.segment_count === 1001 && result.segments.length <= 12);
  assert(
    result.segments[0].index === 1 && result.segments.at(-1)?.index === 1001,
  );
});
Deno.test("구간 심박의 중복 번호·추가 식별자·전체보다 많은 표본을 거부합니다", () => {
  const heart = { average_bpm: 145, max_bpm: 170, sample_count: 3 };
  for (
    const segments of [
      [{ index: 1, ...heart }, { index: 1, ...heart }],
      [{ index: 1, ...heart, sample_count: 4 }],
      [{ index: 1, ...heart, device_id: "private" }],
      [{ index: 1, ...heart, segments: [] }],
    ]
  ) {
    let rejected = false;
    try {
      safeHeartSummary({ ...heart, segments });
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("AI 입력은 선택된 구간 심박·숫자 요약만 포함하고 날짜·좌표·기기명은 제외합니다", async () => {
  const context = buildRunContext(raw);
  const summary: Summary = {
    current: { distance_m: 2000, duration_sec: 630, pace_seconds_per_km: 315 },
    previous: {
      count: 0,
      total_distance_m: 0,
      total_duration_sec: 0,
      average_distance_m: null,
      pace_seconds_per_km: null,
    },
    context: safeRunContext(context),
    heart_summary: {
      average_bpm: 145,
      max_bpm: 170,
      sample_count: 3,
      segments: [
        { index: 1, average_bpm: 140, max_bpm: 150, sample_count: 1 },
        { index: 2, average_bpm: 150, max_bpm: 170, sample_count: 1 },
        { index: 999, average_bpm: 145, max_bpm: 150, sample_count: 1 },
      ],
    },
  };
  const provider = new GeminiFeedback(
    "test",
    (async (_, options) => {
      const body = JSON.parse(options!.body as string);
      const input = JSON.parse(body.contents[0].parts[0].text);
      assert(input.heart_summary.segments.length === 2);
      assert(input.context.segments[1].previous_segment_difference_sec === 30);
      assert(
        !body.contents[0].parts[0].text.includes("2026-") && !input.latitude &&
          !input.device_id,
      );
      return Response.json({
        candidates: [{
          finishReason: "STOP",
          content: {
            parts: [{
              text: JSON.stringify({
                message:
                  "2km 구간 페이스는 5분 30초/km로 직전보다 30초/km 느렸다. 같은 구간의 상승고도 약 15m가 원인 후보이다. 다음에는 비슷한 경사 구간의 페이스와 심박을 함께 비교해야 한다.",
              }),
            }],
          },
        }],
        usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 100 },
      });
    }) as typeof fetch,
  );
  const result = await provider.generate(summary);
  assert(result.message.includes("30초/km"));
});
