export const MODEL = "gemini-3.5-flash-lite";
export type Summary = {
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
      "한국어 존댓말로 러닝 기록 피드백을 3문장, 총 350자 이내로 작성하세요. " +
      "첫 문장은 기록에 근거한 잘한 점, 둘째 문장은 이전 기록과의 변화, 셋째 문장은 간단한 기록 관리 제안입니다. " +
      "previous는 해당 러닝 시작 전 30일 내 최대 5회 기록의 합산 요약입니다. " +
      "count가 0이면 비교 기록이 없다고 명시하세요. 페이스는 값이 작을수록 빠릅니다. " +
      "거리와 환경이 다를 수 있으므로 페이스 변화만으로 체력 향상을 단정하지 마세요. " +
      "측정값은 개인 기기 기록이며 검증된 운동 성과가 아닙니다. " +
      "부상·질병·심박·칼로리를 추측하거나 의료 진단, 훈련 강도 증가, 속도 경쟁, 보상 지급을 제안하지 마세요. " +
      "제공하지 않은 수치나 사실을 만들지 말고 HTML, 링크, 마크다운을 사용하지 마세요.";
    const content = JSON.stringify(safeSummary(summary));
    if (new TextEncoder().encode(instruction + content).length > 4096) {
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
      !message || [...message].length > 500 || !/[가-힣]/.test(message) ||
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
