import proj4 from "proj4";
import { distance } from "@turf/distance";
import {
  Provider,
  ProviderFailure,
  SharedCache,
  SharedLoader,
} from "./shared_cache.ts";
export { ProviderFailure } from "./shared_cache.ts";

export type Row = Record<string, unknown>;

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
  private loader: SharedLoader;
  constructor(
    cache: SharedCache,
    private keys: { kma: string; air: string },
    private fetcher: typeof fetch = fetch,
  ) {
    this.loader = new SharedLoader(cache);
  }

  private async request(
    path: string,
    key: string,
    parameters: Record<string, string>,
    reserve: (provider: Provider) => Promise<void>,
    provider: Provider,
  ): Promise<{ rows: Row[]; total: number }> {
    if (!key) throw new ProviderFailure("not_configured");
    const url = new URL(`https://apis.data.go.kr/${path}`);
    url.search = new URLSearchParams({
      ...parameters,
      serviceKey: decodeURIComponent(key),
    }).toString();
    await reserve(provider);
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
      const total = Number(data.body.totalCount);
      if (
        !Number.isSafeInteger(total) || total < rows.length || total > 10000
      ) {
        throw new ProviderFailure("invalid_response");
      }
      return { rows, total };
    } catch (error) {
      if (error instanceof ProviderFailure) throw error;
      throw new ProviderFailure("provider_unavailable");
    }
  }

  async getWeather(location: [number, number], now: Date): Promise<Row> {
    const [nx, ny] = grid(location), base = baseTime(now);
    const result = await this.loader.load(
      `weather:v2:${nx}:${ny}`,
      `${base.date}:${base.time}`,
      86400,
      async (reserve) => {
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
          reserve,
          "kma",
        );
        return weather(rows);
      },
    );
    return {
      ...result.value,
      cachedAt: result.updatedAt,
      refreshError: result.refreshError,
    };
  }

  async getDust(location: [number, number]): Promise<Row> {
    const catalog = await this.loader.load(
      "stations:v2",
      "latest",
      86400,
      async (reserve) => {
        const result: Row[] = [];
        for (let page = 1; page <= 10; page++) {
          const { rows, total } = await this.request(
            "B552584/MsrstnInfoInqireSvc/getMsrstnList",
            this.keys.air,
            { returnType: "json", numOfRows: "1000", pageNo: String(page) },
            reserve,
            "stations",
          );
          result.push(...rows);
          if (Number.isFinite(total) && result.length >= total) return result;
          if (!rows.length) throw new ProviderFailure("invalid_response");
        }
        throw new ProviderFailure("invalid_response");
      },
    );
    const stations = catalog.value;
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
    const region = stationRegion(nearest.row.addr);
    if (!region) throw new ProviderFailure("invalid_response");
    const result = await this.loader.load(
      `dust:v2:${region}`,
      "latest",
      3600,
      async (reserve) => {
        const observations: Row[] = [];
        for (let page = 1; page <= 10; page++) {
          const { rows, total } = await this.request(
            "B552584/ArpltnInforInqireSvc/getCtprvnRltmMesureDnsty",
            this.keys.air,
            {
              returnType: "json",
              sidoName: region,
              ver: "1.4",
              numOfRows: "1000",
              pageNo: String(page),
            },
            reserve,
            "air",
          );
          observations.push(...rows);
          if (observations.length >= total) {
            if (!observations.length) throw new ProviderFailure("no_data");
            return observations.map((row) => ({
              ...dust(row),
              station: row.stationName,
              stationCode: row.stationCode,
            }));
          }
          if (!rows.length) throw new ProviderFailure("invalid_response");
        }
        throw new ProviderFailure("invalid_response");
      },
    );
    const matches = result.value.filter((row) => row.station === name);
    // 코드가 제공되면 동명의 다른 측정소와 혼동하지 않습니다.
    const matched = nearest.row.stationCode != null
      ? matches.find((row) =>
        String(row.stationCode) === String(nearest.row.stationCode)
      )
      : matches.length === 1
      ? matches[0]
      : undefined;
    if (!matched) throw new ProviderFailure("no_data");
    return {
      ...matched,
      station: name,
      distanceKm: Math.round(nearest.km * 10) / 10,
      cachedAt: result.updatedAt,
      refreshError: result.refreshError ?? catalog.refreshError,
    };
  }
}

export function stationRegion(address: unknown): string | null {
  if (typeof address !== "string") return null;
  const first = address.trim().split(/\s+/)[0];
  const regions: Record<string, string> = {
    서울: "서울",
    서울특별시: "서울",
    부산: "부산",
    부산광역시: "부산",
    대구: "대구",
    대구광역시: "대구",
    인천: "인천",
    인천광역시: "인천",
    대전: "대전",
    대전광역시: "대전",
    울산: "울산",
    울산광역시: "울산",
    세종: "세종",
    세종특별자치시: "세종",
    경기: "경기",
    경기도: "경기",
    강원: "강원",
    강원도: "강원",
    강원특별자치도: "강원",
    충북: "충북",
    충청북도: "충북",
    충남: "충남",
    충청남도: "충남",
    전북: "전북",
    전라북도: "전북",
    전북특별자치도: "전북",
    광주: "전남광주",
    광주광역시: "전남광주",
    전남: "전남광주",
    전라남도: "전남광주",
    전남광주: "전남광주",
    전남광주특별시: "전남광주",
    경북: "경북",
    경상북도: "경북",
    경남: "경남",
    경상남도: "경남",
    제주: "제주",
    제주도: "제주",
    제주특별자치도: "제주",
  };
  return regions[first] ?? null;
}
