import { describe, it, expect, vi } from "vitest";
import { Readable } from "node:stream";
import {
  ExchangeRatesService,
  buildPartitionKey,
  enumerateYearMonths,
} from "./exchange-rates.js";
import type { S3ClientLike } from "./types.js";

describe("enumerateYearMonths", () => {
  it("returns a single entry for same month", () => {
    expect(enumerateYearMonths("2024-01-05", "2024-01-28")).toEqual([
      { year: 2024, month: 1 },
    ]);
  });

  it("returns entries across a year boundary", () => {
    expect(enumerateYearMonths("2023-11-15", "2024-02-10")).toEqual([
      { year: 2023, month: 11 },
      { year: 2023, month: 12 },
      { year: 2024, month: 1 },
      { year: 2024, month: 2 },
    ]);
  });

  it("returns a single entry for a single day", () => {
    expect(enumerateYearMonths("2024-07-10", "2024-07-10")).toEqual([
      { year: 2024, month: 7 },
    ]);
  });
});

describe("buildPartitionKey", () => {
  it("zero-pads month below 10", () => {
    expect(buildPartitionKey("gold/exchange_rates", 1999, 7)).toBe(
      "gold/exchange_rates/year=1999/month=07/data.parquet",
    );
  });

  it("keeps month of 10 or more as two digits", () => {
    expect(buildPartitionKey("gold/exchange_rates", 2024, 12)).toBe(
      "gold/exchange_rates/year=2024/month=12/data.parquet",
    );
  });

  it("respects a custom prefix", () => {
    expect(buildPartitionKey("custom/prefix", 2024, 3)).toBe(
      "custom/prefix/year=2024/month=03/data.parquet",
    );
  });
});

function makeS3Mock(
  responses: Map<string, { body?: unknown; error?: unknown }>,
): { client: S3ClientLike; calls: string[] } {
  const calls: string[] = [];
  const client: S3ClientLike = {
    send: vi.fn(async (cmd: unknown) => {
      // @aws-sdk GetObjectCommand exposes input on the instance
      const input = (cmd as { input: { Bucket: string; Key: string } }).input;
      calls.push(input.Key);
      const entry = responses.get(input.Key);
      if (!entry) {
        const err = new Error("NoSuchKey") as Error & { name: string };
        err.name = "NoSuchKey";
        throw err;
      }
      if (entry.error) throw entry.error;
      return { Body: entry.body };
    }),
  };
  return { client, calls };
}

function bodyFromString(str: string): Readable {
  return Readable.from([Buffer.from(str)]);
}

describe("ExchangeRatesService.getRates", () => {
  const bucket = "test-bucket";

  it("throws when bucket is empty", async () => {
    const service = new ExchangeRatesService({
      s3Client: { send: vi.fn() },
      bucket: "",
      readParquet: async () => [],
    });
    await expect(
      service.getRates({ dateFrom: "2024-01-01", dateTo: "2024-01-31" }),
    ).rejects.toThrow("AWS_S3_BUCKET_NAME is not configured");
  });

  it("throws when dateFrom > dateTo", async () => {
    const service = new ExchangeRatesService({
      s3Client: { send: vi.fn() },
      bucket,
      readParquet: async () => [],
    });
    await expect(
      service.getRates({ dateFrom: "2024-02-01", dateTo: "2024-01-01" }),
    ).rejects.toThrow("dateFrom must be <= dateTo");
  });

  it("throws when range exceeds maxMonths", async () => {
    const service = new ExchangeRatesService({
      s3Client: { send: vi.fn() },
      bucket,
      readParquet: async () => [],
      maxMonths: 3,
    });
    await expect(
      service.getRates({ dateFrom: "2024-01-01", dateTo: "2024-06-30" }),
    ).rejects.toThrow(/exceeds maximum/);
  });

  it("reads a single partition and filters rows by date range", async () => {
    const responses = new Map([
      [
        "gold/exchange_rates/year=2024/month=01/data.parquet",
        { body: bodyFromString("parquet-bytes-1") },
      ],
    ]);
    const { client } = makeS3Mock(responses);
    const readParquet = vi.fn().mockResolvedValue([
      { date: "2023-12-31", base: "USD", quote: "KRW", rate: 1290 }, // out of range
      { date: "2024-01-10", base: "USD", quote: "KRW", rate: 1310 },
      { date: "2024-01-20", base: "USD", quote: "KRW", rate: 1320 },
      { date: "2024-02-01", base: "USD", quote: "KRW", rate: 1330 }, // out of range
    ]);

    const service = new ExchangeRatesService({
      s3Client: client,
      bucket,
      readParquet,
    });

    const rows = await service.getRates({
      dateFrom: "2024-01-10",
      dateTo: "2024-01-25",
    });

    expect(rows).toHaveLength(2);
    expect(rows.map((r) => r.date)).toEqual(["2024-01-10", "2024-01-20"]);
    expect(readParquet).toHaveBeenCalledTimes(1);
  });

  it("concatenates rows from multiple partitions in order", async () => {
    const responses = new Map([
      [
        "gold/exchange_rates/year=2024/month=01/data.parquet",
        { body: bodyFromString("jan") },
      ],
      [
        "gold/exchange_rates/year=2024/month=02/data.parquet",
        { body: bodyFromString("feb") },
      ],
    ]);
    const { client, calls } = makeS3Mock(responses);
    const readParquet = vi
      .fn()
      .mockResolvedValueOnce([{ date: "2024-01-15", rate: 1300 }])
      .mockResolvedValueOnce([{ date: "2024-02-10", rate: 1340 }]);

    const service = new ExchangeRatesService({
      s3Client: client,
      bucket,
      readParquet,
    });

    const rows = await service.getRates({
      dateFrom: "2024-01-01",
      dateTo: "2024-02-28",
    });

    expect(rows).toHaveLength(2);
    expect(rows[0].date).toBe("2024-01-15");
    expect(rows[1].date).toBe("2024-02-10");
    expect(calls).toEqual([
      "gold/exchange_rates/year=2024/month=01/data.parquet",
      "gold/exchange_rates/year=2024/month=02/data.parquet",
    ]);
  });

  it("skips missing partitions (NoSuchKey) and continues", async () => {
    const responses = new Map([
      [
        "gold/exchange_rates/year=2024/month=02/data.parquet",
        { body: bodyFromString("feb") },
      ],
    ]);
    const { client } = makeS3Mock(responses);
    const readParquet = vi
      .fn()
      .mockResolvedValueOnce([{ date: "2024-02-10", rate: 1340 }]);

    const warn = vi.fn();
    const service = new ExchangeRatesService({
      s3Client: client,
      bucket,
      readParquet,
      logger: { info: vi.fn(), warn, error: vi.fn(), debug: vi.fn() },
    });

    const rows = await service.getRates({
      dateFrom: "2024-01-01",
      dateTo: "2024-02-28",
    });

    expect(rows).toHaveLength(1);
    expect(rows[0].date).toBe("2024-02-10");
    expect(warn).toHaveBeenCalledWith(
      "Exchange rate partition not found, skipping",
      expect.objectContaining({
        key: "gold/exchange_rates/year=2024/month=01/data.parquet",
      }),
    );
  });

  it("propagates non-404 S3 errors", async () => {
    const responses = new Map([
      [
        "gold/exchange_rates/year=2024/month=01/data.parquet",
        { error: Object.assign(new Error("Access Denied"), { name: "AccessDenied" }) },
      ],
    ]);
    const { client } = makeS3Mock(responses);

    const service = new ExchangeRatesService({
      s3Client: client,
      bucket,
      readParquet: async () => [],
    });

    await expect(
      service.getRates({ dateFrom: "2024-01-01", dateTo: "2024-01-31" }),
    ).rejects.toThrow("Access Denied");
  });

  it("skips rows missing a string 'date' column", async () => {
    const responses = new Map([
      [
        "gold/exchange_rates/year=2024/month=01/data.parquet",
        { body: bodyFromString("jan") },
      ],
    ]);
    const { client } = makeS3Mock(responses);
    const readParquet = vi.fn().mockResolvedValue([
      { date: "2024-01-15", rate: 1300 },
      { rate: 9999 }, // missing date
      { date: 20240116, rate: 1301 }, // not a string
    ]);

    const service = new ExchangeRatesService({
      s3Client: client,
      bucket,
      readParquet,
    });

    const rows = await service.getRates({
      dateFrom: "2024-01-01",
      dateTo: "2024-01-31",
    });

    expect(rows).toHaveLength(1);
    expect(rows[0].date).toBe("2024-01-15");
  });
});
