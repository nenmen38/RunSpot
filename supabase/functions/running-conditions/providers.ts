import proj4 from "proj4";
import { distance } from "@turf/distance";

export type Row = Record<string, unknown>;
export interface Cache {
  read(key: string): Promise<unknown>;
  write(key: string, value: unknown, ttl: number): Promise<void>;
}
export class ProviderFailure extends Error {
  constructor(public code: string) {
    super(code);
  }
}

export function coordinate(body: unknown): [number, number] {
  const row = body as Row;
  const lat = row?.latitude, lon = row?.longitude;
  if (
    typeof lat !== "number" || typeof lon !== "number" ||
    !Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 ||
    Math.abs(lon) > 180
  ) {
    throw new ProviderFailure("invalid_location");
  }
  // 정밀 GPS 좌표를 외부 서비스나 관측 자료 캐시에 남기지 않습니다.
  return [Math.round(lat * 100) / 100, Math.round(lon * 100) / 100];
}
export function supported([lat, lon]: [number, number]): boolean {
  return lat >= 33 && lat <= 38.7 && lon >= 124.5 && lon <= 132;
}
export function grid([lat, lon]: [number, number]): [number, number] {
  // 기상청 2026년 9월 기술문서의 구면 반경·표준위도·원점과 동일합니다.
  const [x, y] = proj4(
    "+proj=longlat +a=6371008.77 +b=6371008.77 +no_defs",
    "+proj=lcc +lat_1=30 +lat_2=60 +lat_0=38 +lon_0=126 +a=6371008.77 +b=6371008.77 +units=m +no_defs",
    [lon, lat],
  );
  return [Math.round(x / 5000 + 43), Math.round(y / 5000 + 136)];
}
export function baseTime(now: Date): { date: string; time: string } {
  // 초단기실황은 매시 10분 이후 제공됩니다. 갱신 경계에 2분 여유를 둡니다.
  const kst = new Date(now.getTime() + 9 * 3600000 - 12 * 60000);
  return {
    date: kst.toISOString().slice(0, 10).replaceAll("-", ""),
    time: `${String(kst.getUTCHours()).padStart(2, "0")}00`,
  };
}
export function kstTime(text: unknown): string | null {
  if (typeof text !== "string") return null;
  const match = /^(\d{4})-?(\d{2})-?(\d{2})[ T](\d{2}):?(\d{2})$/.exec(text);
  if (!match) return null;
  const [, year, month, day, hour, minute] = match;
  if (
    +month < 1 || +month > 12 || +day < 1 || +day > 31 || +hour > 24 ||
    +minute > 59 || (+hour === 24 && +minute !== 0)
  ) return null;
  const result = new Date(
    `${year}-${month}-${day}T${hour === "24" ? "00" : hour}:${minute}:00+09:00`,
  );
  if (!Number.isFinite(result.getTime())) return null;
  const local = new Date(result.getTime() + 9 * 3600000);
  if (
    local.getUTCFullYear() !== +year || local.getUTCMonth() + 1 !== +month ||
    local.getUTCDate() !== +day
  ) return null;
  if (+hour === 24) result.setUTCDate(result.getUTCDate() + 1);
  return result.toISOString();
}
export function number(
  value: unknown,
  min: number,
  max: number,
): number | null {
  if (
    (typeof value !== "string" && typeof value !== "number") || value === "" ||
    (typeof value === "string" && !value.trim())
  ) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= min && parsed <= max
    ? parsed
    : null;
}
export function weather(rows: Row[]): Row {
  const first = rows[0];
  if (!first) throw new ProviderFailure("no_data");
  const values = new Map(
    rows.filter((row) =>
      row.baseDate === first.baseDate && row.baseTime === first.baseTime
    ).map((row) => [row.category, row.obsrValue]),
  );
  const precipitation = number(values.get("PTY"), 0, 7);
  return {
    observedAt: kstTime(`${first.baseDate} ${first.baseTime}`),
    temperature: number(values.get("T1H"), -80, 60),
    rain: number(values.get("RN1"), 0, 1000),
    precipitation: precipitation !== null && Number.isInteger(precipitation)
      ? precipitation
      : null,
    wind: number(values.get("WSD"), 0, 150),
  };
}
export function dust(row: Row): Row {
  return {
    observedAt: kstTime(row.dataTime),
    pm10: row.pm10Flag ? null : number(row.pm10Value, 0, 10000),
    pm25: row.pm25Flag ? null : number(row.pm25Value, 0, 10000),
  };
}

export class Providers {
  constructor(
    private cache: Cache,
    private keys: { kma: string; air: string },
    private fetcher: typeof fetch = fetch,
  ) {}

  private async load(
    key: string,
    ttl: number,
    loader: () => Promise<unknown>,
  ): Promise<unknown> {
    const cached = await this.cache.read(key);
    if (cached !== null && cached !== undefined) return cached;
    const value = await loader();
    await this.cache.write(key, value, ttl);
    return value;
  }

  private async request(
    path: string,
    key: string,
    parameters: Record<string, string>,
  ): Promise<{ rows: Row[]; total: number }> {
    if (!key) throw new ProviderFailure("not_configured");
    const url = new URL(`https://apis.data.go.kr/${path}`);
    url.search = new URLSearchParams({
      ...parameters,
      serviceKey: decodeURIComponent(key),
    }).toString();
    try {
      const response = await this.fetcher(url, {
        signal: AbortSignal.timeout(10000),
        redirect: "error",
      });
      if (!response.ok) {
        throw new ProviderFailure(
          response.status === 403
            ? "permission_denied"
            : "provider_unavailable",
        );
      }
      // 정상 요청도 인증 오류 시 XML이 올 수 있습니다. 원문과 요청 URL은 반환하지 않습니다.
      const reader = response.body?.getReader();
      if (!reader) throw new ProviderFailure("no_data");
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        size += chunk.value.length;
        if (size > 2000000) {
          await reader.cancel();
          throw new ProviderFailure("invalid_response");
        }
        chunks.push(chunk.value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      const data = JSON.parse(new TextDecoder().decode(bytes)).response;
      if (data?.header?.resultCode !== "00") {
        throw new ProviderFailure("provider_unavailable");
      }
      const rows = Array.isArray(data.body?.items)
        ? data.body.items
        : data.body?.items?.item;
      if (!Array.isArray(rows)) throw new ProviderFailure("no_data");
      return { rows, total: Number(data.body.totalCount) };
    } catch (error) {
      if (error instanceof ProviderFailure) throw error;
      throw new ProviderFailure("provider_unavailable");
    }
  }

  async getWeather(location: [number, number], now: Date): Promise<Row> {
    const [nx, ny] = grid(location), base = baseTime(now);
    const value = await this.load(
      `weather:${nx}:${ny}:${base.date}:${base.time}`,
      300,
      async () => {
        const { rows } = await this.request(
          "1360000/VilageFcstInfoService_2.0/getUltraSrtNcst",
          this.keys.kma,
          {
            dataType: "JSON",
            base_date: base.date,
            base_time: base.time,
            nx: String(nx),
            ny: String(ny),
            numOfRows: "100",
            pageNo: "1",
          },
        );
        return weather(rows);
      },
    );
    return value as Row;
  }

  async getDust(location: [number, number]): Promise<Row> {
    const stations = await this.load("stations:v1", 86400, async () => {
      const result: Row[] = [];
      for (let page = 1; page <= 10; page++) {
        const { rows, total } = await this.request(
          "B552584/MsrstnInfoInqireSvc/getMsrstnList",
          this.keys.air,
          { returnType: "json", numOfRows: "1000", pageNo: String(page) },
        );
        result.push(...rows);
        if (Number.isFinite(total) && result.length >= total) return result;
        if (!rows.length) throw new ProviderFailure("invalid_response");
      }
      throw new ProviderFailure("invalid_response");
    }) as Row[];
    const candidates = stations.filter((row) =>
      typeof row.stationName === "string" &&
      number(row.dmX, 33, 38.7) !== null &&
      number(row.dmY, 124.5, 132) !== null &&
      typeof row.item === "string" && row.item.includes("PM10") &&
      row.item.includes("PM2.5")
    )
      .map((row) => ({
        row,
        km: distance([location[1], location[0]], [
          Number(row.dmY),
          Number(row.dmX),
        ]),
      }))
      .sort((a, b) => a.km - b.km);
    const nearest = candidates[0];
    if (!nearest || nearest.km > 30) {
      throw new ProviderFailure("no_nearby_station");
    }
    const name = String(nearest.row.stationName);
    const value = await this.load(`dust:${name}`, 600, async () => {
      const { rows } = await this.request(
        "B552584/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty",
        this.keys.air,
        {
          returnType: "json",
          stationName: name,
          dataTerm: "DAILY",
          ver: "1.3",
          numOfRows: "1",
          pageNo: "1",
        },
      );
      if (!rows.length) throw new ProviderFailure("no_data");
      return dust(rows[0]);
    }) as Row;
    return {
      ...value,
      station: name,
      distanceKm: Math.round(nearest.km * 10) / 10,
    };
  }
}
