import { type RunContext, safeRunContext } from "./run_context.ts";
import { feedbackComparison } from "./comparison.ts";
import { type HeartSummary, safeHeartSummary } from "./heart_summary.ts";

export const MODEL = "gemini-3.5-flash-lite";
export type Summary = {
  heart_summary?: HeartSummary;
  context?: RunContext;
  current: {
    distance_m: number;
    duration_sec: number;
    pace_seconds_per_km: number;
  };
  previous: {
    count: number;
    total_distance_m: number;
    total_duration_sec: number;
    average_distance_m: number | null;
    pace_seconds_per_km: number | null;
  };
};
export type Feedback = {
  message: string;
  inputTokens: number;
  outputTokens: number;
};

// 외부 전송 항목은 숫자 요약만 허용하고 식별자·날짜·좌표·사용자 문자열을 제외합니다.
export function safeSummary(input: Summary): Summary {
  function integer(value: unknown, nullable = false): number | null {
    if (nullable && value === null) return null;
    if (
      !Number.isSafeInteger(value) || (value as number) < 0 ||
      (value as number) > 100000000
    ) {
      throw new Error("invalid_summary");
    }
    return value as number;
  }
  return {
    ...(input.context === undefined
      ? {}
      : { context: safeRunContext(input.context) }),
    ...(input.heart_summary === undefined
      ? {}
      : { heart_summary: safeHeartSummary(input.heart_summary) }),
    current: {
      distance_m: integer(input.current.distance_m)!,
      duration_sec: integer(input.current.duration_sec)!,
      pace_seconds_per_km: integer(input.current.pace_seconds_per_km)!,
    },
    previous: {
      count: integer(input.previous.count)!,
      total_distance_m: integer(input.previous.total_distance_m)!,
      total_duration_sec: integer(input.previous.total_duration_sec)!,
      average_distance_m: integer(input.previous.average_distance_m, true),
      pace_seconds_per_km: integer(input.previous.pace_seconds_per_km, true),
    },
  };
}
export async function boundedJson(
  response: Response,
  limit = 32768,
): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("empty_response");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > limit) {
      await reader.cancel();
      throw new Error("large_response");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}
export class GeminiFeedback {
  constructor(private key: string, private fetcher: typeof fetch = fetch) {}
  async generate(summary: Summary): Promise<Feedback> {
    const instruction =
      "감정을 배제한 냉정하고 객관적인 한국어 반말로 러닝 피드백을 3문장, 총 150자 이내로 작성해. 문장은 했다·이다·없다처럼 간결한 서술형으로 끝내. " +
      "수치 비교 → 근거 있는 해석 → 개선 행동 하나 순서로 써. 마지막 문장에는 다음에 할 행동과 확인할 지표를 함께 제시해. 원인이 불명확하면 원인 확인을 위한 기록·비교 방법을 제안해. " +
      "칭찬·격려·위로·인사·훈계·비난·과장·감탄사·이모지와 성격·의지·노력 평가는 금지해. 핵심 수치를 생략하지 마. " +
      "previous는 이번 러닝 시작 전 30일 내 최대 5회 합산 요약이야. count가 0이면 비교 자료가 없다고 짧게 명시해. 비교 페이스는 이전 총 시간/총 거리 기준이고 거리는 이전 평균 거리 기준으로 비교해. 합산 요약으로 연속 향상이나 악화 추세를 주장하지 마. " +
      "크게·조금·많이·상당히·소폭·대폭 같은 추상적인 증감 표현은 금지해. 비교에는 현재 값·이전 기준값·차이를 숫자와 단위로 명시해. " +
      "comparison은 서버가 계산한 현재-이전 차이야. distance_difference_m은 이전 평균 거리 대비 m 차이이고, pace_difference_seconds_per_km은 이전 합산 페이스 대비 초/km 차이야. 음수 페이스 차이는 빨라진 것이고 0이면 동일해. null인 항목은 비교하지 마. " +
      "거리는 m 또는 km, 페이스는 분·초/km, 심박은 회/분으로 써. 반올림하면 약이라고 표시하고, 150자를 맞추려고 수치 대신 추상적인 말을 쓰지 마. " +
      "거리·환경 차이가 있어 체력 향상이나 변화 원인을 단정하지 마. 구간 자료가 없을 때 초반 과속·후반 저하를 주장하지 마. 비교 자료가 없으면 다음 기록에서 비교할 지표를 제안해. " +
      "heart_summary가 있으면 기기에서 읽은 평균·최대 심박(회/분)과 표본 수를 참고해 심박 관찰을 한 문장에 포함해. " +
      "심박은 클라이언트 제공 참고값이며 시작~종료 구간의 표본 산술 평균·최댓값이고 일시 정지도 포함해. " +
      "표본 수는 측정 시간이나 전체 구간의 수집률이 아니야. 최대 심박은 관측 최댓값이지 개인의 최대 능력이 아니야. " +
      "context의 구간 페이스·고도·GPS 품질·기온·정지 요약으로 감속 구간과 원인 후보를 분석해. 고도는 오차를 걸러낸 부분 관측 추정이며 관측 거리 밖의 경사·기온 변화는 추정하지 마. 마지막 짧은 구간은 1km 구간과 직접 비교하지 마. 단일 기온이나 심박 상승만으로 더위·피로·탈수를 원인으로 단정하지 마. " +
      "같은 구간의 페이스 저하와 상승고도가 겹치면 오르막 영향을 후보로 제시할 수 있지만 인과관계는 단정하지 마. GPS 제외·단절이 있으면 측정 영향을 함께 고려해. GPS 정확도는 기기 추정 반경이며 실제 거리 오차가 아니야. 일시 정지는 평균 페이스 계산에서 제외되므로 정지 시간을 직접적인 감속 원인으로 삼지 마. " +
      "heart_summary.segments는 정지·미측정 구간과 경계에 걸친 표본을 제외한 구간별 심박이야. 같은 번호의 구간 페이스와 함께 비교할 수 있어. 전체 심박은 정지 포함이라 구간 심박과 집계 범위가 달라. 심박이 없으면 추정하지 마. 회복·의학적 심박 구간·정상 여부·운동 강도·안전성을 판단하지 마. " +
      "개인 기기 기록을 검증된 운동 성과로 단정하지 마. 부상·질병·칼로리를 추측하거나 의료 진단, " +
      "훈련량·속도·심박 목표를 임의로 처방하거나 훈련 강도 증가·속도 경쟁·보상 지급을 제안하지 마. " +
      "제공하지 않은 수치·사실을 만들거나 HTML·링크·마크다운을 쓰지 마. " +
      "말투 예시(실제 수치는 입력만 사용): '거리는 이전 평균 5km에서 3km로 2km 줄었다. 의도한 거리 감소인지는 알 수 없다. 다음에는 목표 거리도 기록해 실제 거리와 차이를 확인해야 한다.'";
    const safe = safeSummary(summary);
    if (safe.heart_summary?.segments && safe.context) {
      const included = new Set(safe.context.segments.map((s) => s.index));
      safe.heart_summary = {
        ...safe.heart_summary,
        segments: safe.heart_summary.segments.filter((s) =>
          included.has(s.index)
        ),
      };
    }
    const content = JSON.stringify({
      ...safe,
      comparison: feedbackComparison(safe),
    });
    if (new TextEncoder().encode(instruction + content).length > 16384) {
      throw new Error("large_prompt");
    }
    const response = await this.fetcher(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": this.key,
        },
        signal: AbortSignal.timeout(35000),
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: instruction }] },
          contents: [{ role: "user", parts: [{ text: content }] }],
          generationConfig: {
            candidateCount: 1,
            maxOutputTokens: 768,
            responseMimeType: "application/json",
            responseSchema: {
              type: "OBJECT",
              properties: { message: { type: "STRING" } },
              required: ["message"],
            },
          },
        }),
      },
    );
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error("provider_unavailable");
    }
    const result = await boundedJson(response) as {
      candidates?: {
        finishReason?: string;
        content?: { parts?: { text?: string; thought?: boolean }[] };
      }[];
      usageMetadata?: {
        promptTokenCount?: number;
        candidatesTokenCount?: number;
        thoughtsTokenCount?: number;
      };
    };
    const candidate = result.candidates?.[0];
    if (candidate?.finishReason !== "STOP") {
      throw new Error("incomplete_response");
    }
    const parsed = JSON.parse(
      candidate.content?.parts?.filter((part) => !part.thought)
        .map((part) => part.text ?? "").join("") ?? "",
    );
    const message = typeof parsed.message === "string"
      ? parsed.message.trim()
      : "";
    if (
      !message || [...message].length > 150 || !/[가-힣]/.test(message) ||
      /https?:|<[^>]*>/.test(message)
    ) {
      throw new Error("invalid_response");
    }
    const usage = result.usageMetadata;
    const inputTokens = usage?.promptTokenCount;
    const outputTokens = (usage?.candidatesTokenCount ?? 0) +
      (usage?.thoughtsTokenCount ?? 0);
    if (
      !Number.isSafeInteger(inputTokens) || inputTokens! < 0 ||
      !Number.isSafeInteger(outputTokens) || outputTokens < 0
    ) {
      throw new Error("invalid_usage");
    }
    return { message, inputTokens: inputTokens!, outputTokens };
  }
}
