import type { Summary } from "./gemini.ts";

// 검증된 요약값의 차이를 서버에서 계산합니다. 음수 페이스 차이는 더 빠른 기록입니다.
export function feedbackComparison(summary: Summary) {
  const previous = summary.previous;
  return {
    distance_difference_m:
      previous.count > 0 && previous.average_distance_m !== null
        ? summary.current.distance_m - previous.average_distance_m
        : null,
    pace_difference_seconds_per_km:
      previous.count > 0 && previous.pace_seconds_per_km !== null &&
        previous.pace_seconds_per_km > 0 &&
        summary.current.pace_seconds_per_km > 0
        ? summary.current.pace_seconds_per_km - previous.pace_seconds_per_km
        : null,
  };
}
