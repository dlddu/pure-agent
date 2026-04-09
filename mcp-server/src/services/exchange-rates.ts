import { GetObjectCommand } from "@aws-sdk/client-s3";
import { createLogger, type Logger } from "../logger.js";
import type {
  ExchangeRateRow,
  ExchangeRatesServiceOptions,
  GetRatesInput,
  IExchangeRatesService,
  S3ClientLike,
} from "./types.js";

const DEFAULT_PREFIX = "gold/exchange_rates";
const DEFAULT_MAX_MONTHS = 12;

const noopLogger: Logger = {
  info: () => {},
  warn: () => {},
  error: () => {},
  debug: () => {},
};

export function enumerateYearMonths(
  from: string,
  to: string,
): Array<{ year: number; month: number }> {
  const [fromYear, fromMonth] = parseYearMonth(from);
  const [toYear, toMonth] = parseYearMonth(to);

  const result: Array<{ year: number; month: number }> = [];
  let year = fromYear;
  let month = fromMonth;
  while (year < toYear || (year === toYear && month <= toMonth)) {
    result.push({ year, month });
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  return result;
}

export function buildPartitionKey(
  prefix: string,
  year: number,
  month: number,
): string {
  const mm = String(month).padStart(2, "0");
  return `${prefix}/year=${year}/month=${mm}/data.parquet`;
}

function parseYearMonth(date: string): [number, number] {
  const [yStr, mStr] = date.split("-");
  return [Number(yStr), Number(mStr)];
}

function isNotFoundError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const e = err as { name?: string; $metadata?: { httpStatusCode?: number }; Code?: string };
  if (e.name === "NoSuchKey" || e.name === "NotFound") return true;
  if (e.Code === "NoSuchKey") return true;
  if (e.$metadata?.httpStatusCode === 404) return true;
  return false;
}

async function streamToUint8Array(body: unknown): Promise<Uint8Array> {
  if (body == null) {
    return new Uint8Array(0);
  }
  // Web ReadableStream (has getReader)
  if (typeof (body as { getReader?: unknown }).getReader === "function") {
    const reader = (body as ReadableStream<Uint8Array>).getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        total += value.byteLength;
      }
    }
    return concatChunks(chunks, total);
  }
  // Node Readable (async iterable)
  if (typeof (body as AsyncIterable<unknown>)[Symbol.asyncIterator] === "function") {
    const chunks: Uint8Array[] = [];
    let total = 0;
    for await (const chunk of body as AsyncIterable<Uint8Array | Buffer>) {
      const buf = chunk instanceof Uint8Array ? chunk : new Uint8Array(chunk as Buffer);
      chunks.push(buf);
      total += buf.byteLength;
    }
    return concatChunks(chunks, total);
  }
  // Buffer / Uint8Array
  if (body instanceof Uint8Array) {
    return body;
  }
  throw new Error("Unsupported S3 Body type");
}

function concatChunks(chunks: Uint8Array[], total: number): Uint8Array {
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

export class ExchangeRatesService implements IExchangeRatesService {
  private s3Client: S3ClientLike;
  private bucket: string;
  private prefix: string;
  private readParquet: (bytes: Uint8Array) => Promise<Record<string, unknown>[]>;
  private logger: Logger;
  private maxMonths: number;

  constructor(options: ExchangeRatesServiceOptions) {
    this.s3Client = options.s3Client;
    this.bucket = options.bucket;
    this.prefix = options.prefix ?? DEFAULT_PREFIX;
    this.readParquet = options.readParquet;
    this.logger = options.logger ?? noopLogger;
    this.maxMonths = options.maxMonths ?? DEFAULT_MAX_MONTHS;
  }

  async getRates({ dateFrom, dateTo }: GetRatesInput): Promise<ExchangeRateRow[]> {
    if (!this.bucket) {
      throw new Error("AWS_S3_BUCKET_NAME is not configured");
    }
    if (dateFrom > dateTo) {
      throw new Error("dateFrom must be <= dateTo");
    }

    const partitions = enumerateYearMonths(dateFrom, dateTo);
    if (partitions.length > this.maxMonths) {
      throw new Error(
        `Date range spans ${partitions.length} months, exceeds maximum of ${this.maxMonths}`,
      );
    }

    this.logger.info("Fetching exchange rate partitions", {
      bucket: this.bucket,
      prefix: this.prefix,
      dateFrom,
      dateTo,
      partitionCount: partitions.length,
    });

    const allRows: ExchangeRateRow[] = [];

    for (const { year, month } of partitions) {
      const key = buildPartitionKey(this.prefix, year, month);
      let bytes: Uint8Array;
      try {
        const response = await this.s3Client.send(
          new GetObjectCommand({ Bucket: this.bucket, Key: key }),
        );
        bytes = await streamToUint8Array(response.Body);
      } catch (err) {
        if (isNotFoundError(err)) {
          this.logger.warn("Exchange rate partition not found, skipping", { key });
          continue;
        }
        throw err;
      }

      const rows = await this.readParquet(bytes);
      for (const row of rows) {
        const date = row.date;
        if (typeof date !== "string") {
          this.logger.warn("Row missing string 'date' column, skipping", { key });
          continue;
        }
        if (date >= dateFrom && date <= dateTo) {
          allRows.push(row as ExchangeRateRow);
        }
      }
    }

    this.logger.info("Fetched exchange rates", {
      dateFrom,
      dateTo,
      rowCount: allRows.length,
    });

    return allRows;
  }
}

export function createExchangeRatesLogger(): Logger {
  return createLogger("exchange-rates");
}
