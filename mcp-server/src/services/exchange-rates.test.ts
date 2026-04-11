import { describe, it, expect, vi, beforeEach } from "vitest";
import { ExchangeRatesService, enumerateMonths } from "./exchange-rates.js";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";

const { stsSendMock, s3SendMock } = vi.hoisted(() => ({
  stsSendMock: vi.fn(),
  s3SendMock: vi.fn(),
}));

vi.mock("@aws-sdk/client-sts", () => ({
  STSClient: vi.fn(),
  AssumeRoleCommand: vi.fn((input) => ({ __type: "AssumeRoleCommand", input })),
}));

vi.mock("@aws-sdk/client-s3", () => ({
  S3Client: vi.fn(),
  ListObjectsV2Command: vi.fn((input) => ({ __type: "ListObjectsV2Command", input })),
  GetObjectCommand: vi.fn((input) => ({ __type: "GetObjectCommand", input })),
}));

function makeCredsResponse() {
  return {
    Credentials: {
      AccessKeyId: "AKIA-test",
      SecretAccessKey: "secret",
      SessionToken: "token",
      Expiration: new Date(Date.now() + 3600_000),
    },
  };
}

describe("enumerateMonths", () => {
  it("returns a single month for dates within the same month", () => {
    expect(enumerateMonths("2026-04-01", "2026-04-30")).toEqual([
      { year: "2026", month: "04" },
    ]);
  });

  it("returns a single month when start equals end", () => {
    expect(enumerateMonths("2026-04-11", "2026-04-11")).toEqual([
      { year: "2026", month: "04" },
    ]);
  });

  it("crosses month boundaries inclusively", () => {
    expect(enumerateMonths("2026-03-30", "2026-05-02")).toEqual([
      { year: "2026", month: "03" },
      { year: "2026", month: "04" },
      { year: "2026", month: "05" },
    ]);
  });

  it("crosses year boundaries", () => {
    expect(enumerateMonths("1999-11-15", "2000-02-01")).toEqual([
      { year: "1999", month: "11" },
      { year: "1999", month: "12" },
      { year: "2000", month: "01" },
      { year: "2000", month: "02" },
    ]);
  });
});

describe("ExchangeRatesService", () => {
  beforeEach(() => {
    stsSendMock.mockReset();
    s3SendMock.mockReset();
    // restoreMocks: true wipes implementations between tests, so re-establish them here.
    vi.mocked(STSClient).mockImplementation(() => ({ send: stsSendMock }) as unknown as STSClient);
    vi.mocked(S3Client).mockImplementation(() => ({ send: s3SendMock }) as unknown as S3Client);
    vi.mocked(AssumeRoleCommand).mockImplementation(
      (input) => ({ __type: "AssumeRoleCommand", input }) as unknown as AssumeRoleCommand,
    );
    vi.mocked(ListObjectsV2Command).mockImplementation(
      (input) => ({ __type: "ListObjectsV2Command", input }) as unknown as ListObjectsV2Command,
    );
    vi.mocked(GetObjectCommand).mockImplementation(
      (input) => ({ __type: "GetObjectCommand", input }) as unknown as GetObjectCommand,
    );
  });

  describe("configuration", () => {
    it("throws a helpful error when not fully configured", async () => {
      const svc = new ExchangeRatesService({ bucket: "b", region: "ap-northeast-2" });
      await expect(svc.listByDateRange("2026-04-11", "2026-04-11")).rejects.toThrow(
        /not configured.*AWS_S3_BUCKET.*AWS_REGION.*EXCHANGE_RATES_ROLE_ARN/,
      );
    });

    it("throws when start_date > end_date", async () => {
      const svc = new ExchangeRatesService({
        bucket: "b",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/r",
      });
      stsSendMock.mockResolvedValue(makeCredsResponse());
      await expect(svc.listByDateRange("2026-04-12", "2026-04-11")).rejects.toThrow(
        /start_date must be <= end_date/,
      );
    });
  });

  describe("listByDateRange", () => {
    it("assumes role, calls ListObjectsV2 once per month, and aggregates keys", async () => {
      const svc = new ExchangeRatesService({
        bucket: "my-bucket",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/exchange-rates",
      });

      stsSendMock.mockResolvedValue(makeCredsResponse());
      s3SendMock
        .mockResolvedValueOnce({
          Contents: [{ Key: "gold/exchange_rates/year=2026/month=03/data.parquet" }],
          IsTruncated: false,
        })
        .mockResolvedValueOnce({
          Contents: [{ Key: "gold/exchange_rates/year=2026/month=04/data.parquet" }],
          IsTruncated: false,
        });

      // Range spanning two months — should make two ListObjectsV2 calls, one per month.
      const keys = await svc.listByDateRange("2026-03-15", "2026-04-11");

      expect(stsSendMock).toHaveBeenCalledTimes(1);
      expect(s3SendMock).toHaveBeenCalledTimes(2);
      expect(keys).toEqual([
        "gold/exchange_rates/year=2026/month=03/data.parquet",
        "gold/exchange_rates/year=2026/month=04/data.parquet",
      ]);

      const firstCall = s3SendMock.mock.calls[0][0];
      expect(firstCall.input.Bucket).toBe("my-bucket");
      expect(firstCall.input.Prefix).toBe("gold/exchange_rates/year=2026/month=03/");
      const secondCall = s3SendMock.mock.calls[1][0];
      expect(secondCall.input.Prefix).toBe("gold/exchange_rates/year=2026/month=04/");
    });

    it("makes only one ListObjectsV2 call for dates within the same month", async () => {
      const svc = new ExchangeRatesService({
        bucket: "my-bucket",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/exchange-rates",
      });

      stsSendMock.mockResolvedValue(makeCredsResponse());
      s3SendMock.mockResolvedValueOnce({
        Contents: [{ Key: "gold/exchange_rates/year=2026/month=04/data.parquet" }],
        IsTruncated: false,
      });

      const keys = await svc.listByDateRange("2026-04-01", "2026-04-30");
      expect(s3SendMock).toHaveBeenCalledTimes(1);
      expect(keys).toEqual(["gold/exchange_rates/year=2026/month=04/data.parquet"]);
    });

    it("follows pagination via NextContinuationToken", async () => {
      const svc = new ExchangeRatesService({
        bucket: "my-bucket",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/exchange-rates",
      });

      stsSendMock.mockResolvedValue(makeCredsResponse());
      s3SendMock
        .mockResolvedValueOnce({
          Contents: [{ Key: "gold/exchange_rates/year=2026/month=04/a.parquet" }],
          IsTruncated: true,
          NextContinuationToken: "token-1",
        })
        .mockResolvedValueOnce({
          Contents: [{ Key: "gold/exchange_rates/year=2026/month=04/b.parquet" }],
          IsTruncated: false,
        });

      const keys = await svc.listByDateRange("2026-04-11", "2026-04-11");
      expect(keys).toEqual([
        "gold/exchange_rates/year=2026/month=04/a.parquet",
        "gold/exchange_rates/year=2026/month=04/b.parquet",
      ]);
      expect(s3SendMock).toHaveBeenCalledTimes(2);
      const secondCall = s3SendMock.mock.calls[1][0];
      expect(secondCall.input.ContinuationToken).toBe("token-1");
    });

    it("rejects date ranges larger than the allowed month maximum", async () => {
      const svc = new ExchangeRatesService({
        bucket: "my-bucket",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/exchange-rates",
      });
      // 2010-01 .. 2026-04 is 196 months, exceeding MAX_RANGE_MONTHS (120).
      await expect(svc.listByDateRange("2010-01-01", "2026-04-11")).rejects.toThrow(
        /Date range too large/,
      );
    });
  });

  describe("getObject", () => {
    it("returns the object body as a Uint8Array", async () => {
      const svc = new ExchangeRatesService({
        bucket: "my-bucket",
        region: "ap-northeast-2",
        roleArn: "arn:aws:iam::123:role/exchange-rates",
      });

      stsSendMock.mockResolvedValue(makeCredsResponse());
      const bytes = new Uint8Array([10, 20, 30]);
      s3SendMock.mockResolvedValueOnce({
        Body: { transformToByteArray: async () => bytes },
      });

      const result = await svc.getObject("gold/exchange_rates/year=2026/month=04/data.parquet");
      expect(result).toEqual(bytes);

      const call = s3SendMock.mock.calls[0][0];
      expect(call.input.Bucket).toBe("my-bucket");
      expect(call.input.Key).toBe("gold/exchange_rates/year=2026/month=04/data.parquet");
    });
  });
});
