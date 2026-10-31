export type SegmentContext = {
  index: number;
  distance_m: number;
  pace_seconds_per_km: number | null;
  previous_segment_difference_sec: number | null;
  ascent_m: number | null;
  descent_m: number | null;
  elevation_observed_distance_m: number;
  gps_received: number | null;
  gps_rejected: number | null;
  gps_gap_sec: number | null;
  gps_accuracy_mean_m: number | null;
  gps_accuracy_max_m: number | null;
};
export type RunContext = {
  temperature_c: number | null;
  user_pause_sec: number | null;
  gps_pause_sec: number | null;
  unmeasured_sec: number | null;
  segment_count: number;
  segments: SegmentContext[];
};
function number(value: unknown, min: number, max: number): number {
  if (
    typeof value !== "number" || !Number.isFinite(value) || value < min ||
    value > max
  ) throw new Error("invalid_context");
  return value;
}
function rows(value: unknown, width: number, limit: number): number[][] {
  if (!Array.isArray(value) || value.length > limit) {
    throw new Error("invalid_context");
  }
  return value.map((row) => {
    if (!Array.isArray(row) || row.length !== width) {
      throw new Error("invalid_context");
    }
    return row.map((v) => number(v, -1e12, 1e12));
  });
}
// 날짜·좌표·식별자를 외부 입력에 포함하지 않고 구간별 숫자 요약만 추출합니다.
export function buildRunContext(input: unknown): RunContext {
  if (!input || typeof input !== "object") throw new Error("invalid_context");
  const raw = input as Record<string, unknown>;
  const diagnostics = raw.analysis_data as Record<string, unknown> | null;
  const elevation = diagnostics ? rows(diagnostics.elevation, 4, 100000) : [];
  const gps = diagnostics ? rows(diagnostics.gps, 8, 1001) : [];
  const pauses = diagnostics ? rows(diagnostics.pauses, 3, 10000) : [];
  const splitData = raw.split_data ?? [];
  if (!Array.isArray(splitData) || splitData.length > 1001) {
    throw new Error("invalid_context");
  }
  let distance = 0, previousPace: number | null = null, elevationCursor = 0;
  const qualityByIndex = new Map(gps.map((g) => [g[0], g]));
  const all: SegmentContext[] = splitData.map((item, i) => {
    const metres = number(item.distance_m, 0.000001, 1000);
    const duration = number(item.duration_us, 0, 604800000000) / 1e6;
    const start = distance;
    distance += metres;
    const calculatedPace = duration > 0 && metres >= 100
      ? Math.round(duration * 1000 / metres)
      : null;
    const pace = calculatedPace !== null && calculatedPace <= 604800000
      ? calculatedPace
      : null;
    const difference = metres === 1000 && pace !== null && previousPace !== null
      ? pace - previousPace
      : null;
    previousPace = metres === 1000 ? pace : null;
    let up = 0, down = 0, covered = 0;
    while (
      elevationCursor < elevation.length &&
      elevation[elevationCursor][1] <= start
    ) elevationCursor++;
    for (
      let j = elevationCursor;
      j < elevation.length && elevation[j][0] < distance;
      j++
    ) {
      const e = elevation[j];
      const overlap = Math.max(
        0,
        Math.min(distance, e[1]) - Math.max(start, e[0]),
      );
      if (overlap <= 0 || e[1] <= e[0]) continue;
      covered += overlap;
      // 수직 오차 합 이하의 변화는 오르막·내리막 근거로 채택하지 않습니다.
      if (Math.abs(e[2]) <= Math.max(3, e[3])) continue;
      const delta = e[2] * overlap / (e[1] - e[0]);
      if (delta > 0) up += delta;
      else down -= delta;
    }
    const quality = qualityByIndex.get(i + 1);
    return {
      index: i + 1,
      distance_m: Math.round(metres),
      pace_seconds_per_km: pace,
      previous_segment_difference_sec: difference,
      ascent_m: covered > 0 ? Math.round(up) : null,
      descent_m: covered > 0 ? Math.round(down) : null,
      elevation_observed_distance_m: Math.round(covered),
      gps_received: quality?.[1] ?? null,
      gps_rejected: quality?.[2] ?? null,
      gps_gap_sec: quality ? Math.round(quality[4] / 1000) : null,
      gps_accuracy_mean_m: quality && quality[7] > 0
        ? Math.round(quality[5] / quality[7] * 10) / 10
        : null,
      gps_accuracy_max_m: quality && quality[7] > 0 ? quality[6] : null,
    };
  });
  // 긴 러닝은 처음·끝과 감속 폭이 큰 구간 및 바로 앞 구간을 최대 12개 선정합니다.
  const selected = new Set<number>(all.length ? [0, all.length - 1] : []);
  const ranked = all.map((s, i) => ({
    i,
    delta: s.previous_segment_difference_sec ?? -Infinity,
  }))
    .sort((a, b) => b.delta - a.delta || a.i - b.i);
  for (const { i } of ranked) {
    if (selected.size >= 10) break;
    selected.add(i);
    if (i > 0) selected.add(i - 1);
  }
  const seconds = (reason: number[]) =>
    diagnostics
      ? Math.round(
        pauses.filter((p) => reason.includes(p[2])).reduce(
          (s, p) => s + p[1] - p[0],
          0,
        ) / 1000,
      )
      : null;
  let temperature: number | null = null;
  if (
    raw.temperature_c != null &&
    typeof raw.temperature_observed_at === "string" &&
    typeof raw.ended_at === "string"
  ) {
    const age = Date.parse(raw.ended_at) -
      Date.parse(raw.temperature_observed_at);
    if (Number.isFinite(age) && age >= -900000 && age <= 7200000) {
      temperature = number(raw.temperature_c, -80, 60);
    }
  }
  return {
    temperature_c: temperature,
    user_pause_sec: seconds([0]),
    gps_pause_sec: seconds([1]),
    unmeasured_sec: seconds([2, 3]),
    segment_count: all.length,
    segments: all.filter((_, i) => selected.has(i)),
  };
}

export function safeRunContext(value: RunContext): RunContext {
  const optional = (v: unknown, min = 0, max = 1e12) =>
    v === null ? null : number(v, min, max);
  if (!Array.isArray(value.segments) || value.segments.length > 12) {
    throw new Error("invalid_context");
  }
  return {
    temperature_c: optional(value.temperature_c, -80, 60),
    user_pause_sec: optional(value.user_pause_sec, 0, 604800),
    gps_pause_sec: optional(value.gps_pause_sec, 0, 604800),
    unmeasured_sec: optional(value.unmeasured_sec, 0, 604800),
    segment_count: number(value.segment_count, 0, 1001),
    segments: value.segments.map((s) => ({
      index: number(s.index, 1, 1001),
      distance_m: number(s.distance_m, 0, 1000),
      pace_seconds_per_km: optional(s.pace_seconds_per_km, 0, 604800000),
      previous_segment_difference_sec: optional(
        s.previous_segment_difference_sec,
        -604800000,
        604800000,
      ),
      ascent_m: optional(s.ascent_m),
      descent_m: optional(s.descent_m),
      elevation_observed_distance_m: number(
        s.elevation_observed_distance_m,
        0,
        1001,
      ),
      gps_received: optional(s.gps_received),
      gps_rejected: optional(s.gps_rejected),
      gps_gap_sec: optional(s.gps_gap_sec),
      gps_accuracy_mean_m: optional(s.gps_accuracy_mean_m),
      gps_accuracy_max_m: optional(s.gps_accuracy_max_m),
    })),
  };
}
