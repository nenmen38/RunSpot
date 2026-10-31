export type HeartSummary = {
  average_bpm: number;
  max_bpm: number;
  sample_count: number;
  segments?: (Omit<HeartSummary, "segments"> & { index: number })[];
};

// 클라이언트에서 동의한 숫자 요약만 받고 원시 표본·기기 식별자·추가 필드는 거부합니다.
export function safeHeartSummary(input: unknown): HeartSummary {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("invalid_heart_summary");
  }
  const value = input as Record<string, unknown>;
  const fields = ["average_bpm", "max_bpm", "sample_count"];
  if (
    Object.keys(value).some((key) => ![...fields, "segments"].includes(key)) ||
    fields.some((key) => !Number.isSafeInteger(value[key]))
  ) {
    throw new Error("invalid_heart_summary");
  }
  const average = value.average_bpm as number;
  const maximum = value.max_bpm as number;
  const count = value.sample_count as number;
  // 전송값의 형식과 상한만 검사하며 의학적 정상 범위를 판정하지 않습니다.
  if (
    average < 1 || maximum > 1000 || average > maximum || count < 1 ||
    count > 100000000
  ) {
    throw new Error("invalid_heart_summary");
  }
  const result: HeartSummary = {
    average_bpm: average,
    max_bpm: maximum,
    sample_count: count,
  };
  if ("segments" in value) {
    if (!Array.isArray(value.segments) || value.segments.length > 1001) {
      throw new Error("invalid_heart_summary");
    }
    const seen = new Set<number>();
    let total = 0;
    result.segments = value.segments.map((row) => {
      if (!row || typeof row !== "object" || Array.isArray(row)) {
        throw new Error("invalid_heart_summary");
      }
      const { index, ...numbers } = row;
      if (
        !Number.isSafeInteger(index) || index < 1 || index > 1001 ||
        seen.has(index)
      ) throw new Error("invalid_heart_summary");
      seen.add(index);
      if ("segments" in numbers) throw new Error("invalid_heart_summary");
      const segment = safeHeartSummary(numbers);
      if (segment.segments || segment.max_bpm > maximum) {
        throw new Error("invalid_heart_summary");
      }
      total += segment.sample_count;
      return { index, ...segment };
    });
    if (total > count) throw new Error("invalid_heart_summary");
  }
  return result;
}
