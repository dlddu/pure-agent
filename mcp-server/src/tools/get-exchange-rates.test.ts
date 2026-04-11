import { describe, it, expect, vi, beforeEach } from "vitest";
import { parseResponseText, createMockContext } from "../test-utils.js";
import { getExchangeRatesTool } from "./get-exchange-rates.js";
import type { McpToolContext } from "./types.js";

describe("getExchangeRatesTool", () => {
  let context: McpToolContext;
  let mockList: ReturnType<typeof vi.fn>;
  let mockGet: ReturnType<typeof vi.fn>;
  let mockMkdir: ReturnType<typeof vi.fn>;
  let mockWriteBinary: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    context = createMockContext();
    mockList = context.services.exchangeRates.listByDateRange as ReturnType<typeof vi.fn>;
    mockGet = context.services.exchangeRates.getObject as ReturnType<typeof vi.fn>;
    mockMkdir = context.io.fs.mkdir as ReturnType<typeof vi.fn>;
    mockWriteBinary = context.io.fs.writeBinaryFile as ReturnType<typeof vi.fn>;
  });

  describe("input validation", () => {
    it("rejects when no date is provided", async () => {
      const result = await getExchangeRatesTool.handler({}, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("Must provide");
    });

    it("rejects invalid date format", async () => {
      const result = await getExchangeRatesTool.handler({ date: "2026/04/11" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("YYYY-MM-DD");
    });

    it("rejects when date and start_date are both provided", async () => {
      const result = await getExchangeRatesTool.handler(
        { date: "2026-04-11", start_date: "2026-04-01", end_date: "2026-04-11" },
        context,
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("not both");
    });

    it("rejects when only start_date is provided (missing end_date)", async () => {
      const result = await getExchangeRatesTool.handler({ start_date: "2026-04-01" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("Both 'start_date' and 'end_date' are required");
    });

    it("rejects when start_date > end_date", async () => {
      const result = await getExchangeRatesTool.handler(
        { start_date: "2026-04-12", end_date: "2026-04-11" },
        context,
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("start_date must be <= end_date");
    });
  });

  describe("empty result", () => {
    it("returns error when no files are found", async () => {
      mockList.mockResolvedValue([]);
      const result = await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("No exchange rate files found");
      expect(parsed.error).toContain("2026-04-11");
    });
  });

  describe("single date success", () => {
    beforeEach(() => {
      mockList.mockResolvedValue([
        "gold/exchange_rates/date=2026-04-11/part-0000.parquet",
        "gold/exchange_rates/date=2026-04-11/part-0001.parquet",
      ]);
      mockGet
        .mockResolvedValueOnce(new Uint8Array([1, 2, 3]))
        .mockResolvedValueOnce(new Uint8Array([4, 5, 6, 7]));
    });

    it("calls listByDateRange with date on both ends", async () => {
      await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      expect(mockList).toHaveBeenCalledWith("2026-04-11", "2026-04-11");
    });

    it("creates the date directory under workDir/exchange_rates/", async () => {
      await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      expect(mockMkdir).toHaveBeenCalledWith("/work/exchange_rates/2026-04-11", { recursive: true });
    });

    it("writes each downloaded object to the local directory", async () => {
      await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      expect(mockWriteBinary).toHaveBeenCalledTimes(2);
      expect(mockWriteBinary).toHaveBeenNthCalledWith(
        1,
        "/work/exchange_rates/2026-04-11/part-0000.parquet",
        expect.any(Uint8Array),
      );
      expect(mockWriteBinary).toHaveBeenNthCalledWith(
        2,
        "/work/exchange_rates/2026-04-11/part-0001.parquet",
        expect.any(Uint8Array),
      );
    });

    it("returns a success response with files metadata", async () => {
      const result = await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBeUndefined();
      expect(parsed.success).toBe(true);
      expect(parsed.query).toEqual({ date: "2026-04-11" });
      expect(parsed.directory).toBe("/work/exchange_rates/2026-04-11");
      expect(parsed.count).toBe(2);
      expect(parsed.files).toEqual([
        {
          s3_key: "gold/exchange_rates/date=2026-04-11/part-0000.parquet",
          local_path: "/work/exchange_rates/2026-04-11/part-0000.parquet",
          size_bytes: 3,
        },
        {
          s3_key: "gold/exchange_rates/date=2026-04-11/part-0001.parquet",
          local_path: "/work/exchange_rates/2026-04-11/part-0001.parquet",
          size_bytes: 4,
        },
      ]);
    });
  });

  describe("date range success", () => {
    beforeEach(() => {
      mockList.mockResolvedValue([
        "gold/exchange_rates/date=2026-04-10/part-0000.parquet",
        "gold/exchange_rates/date=2026-04-11/part-0000.parquet",
      ]);
      mockGet
        .mockResolvedValueOnce(new Uint8Array([1]))
        .mockResolvedValueOnce(new Uint8Array([2]));
    });

    it("uses <start>_<end> as directory name and nests by partition date", async () => {
      const result = await getExchangeRatesTool.handler(
        { start_date: "2026-04-10", end_date: "2026-04-11" },
        context,
      );
      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.directory).toBe("/work/exchange_rates/2026-04-10_2026-04-11");
      expect(parsed.query).toEqual({ start_date: "2026-04-10", end_date: "2026-04-11" });

      expect(mockMkdir).toHaveBeenCalledWith("/work/exchange_rates/2026-04-10_2026-04-11", { recursive: true });
      expect(mockMkdir).toHaveBeenCalledWith("/work/exchange_rates/2026-04-10_2026-04-11/2026-04-10", { recursive: true });
      expect(mockMkdir).toHaveBeenCalledWith("/work/exchange_rates/2026-04-10_2026-04-11/2026-04-11", { recursive: true });

      expect(mockWriteBinary).toHaveBeenNthCalledWith(
        1,
        "/work/exchange_rates/2026-04-10_2026-04-11/2026-04-10/part-0000.parquet",
        expect.any(Uint8Array),
      );
      expect(mockWriteBinary).toHaveBeenNthCalledWith(
        2,
        "/work/exchange_rates/2026-04-10_2026-04-11/2026-04-11/part-0000.parquet",
        expect.any(Uint8Array),
      );
    });
  });

  describe("service errors", () => {
    it("returns friendly error when service is unconfigured", async () => {
      mockList.mockRejectedValue(
        new Error("Exchange rates service is not configured: set AWS_S3_BUCKET, AWS_REGION, EXCHANGE_RATES_ROLE_ARN"),
      );
      const result = await getExchangeRatesTool.handler({ date: "2026-04-11" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("not configured");
    });
  });
});
