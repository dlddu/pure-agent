import { describe, it, expect, vi, beforeEach } from "vitest";
import type { IExchangeRatesService } from "../services/types.js";
import { parseResponseText, createMockContext } from "../test-utils.js";
import type { McpToolContext } from "./types.js";
import { getExchangeRatesTool } from "./get-exchange-rates.js";

describe("getExchangeRatesTool", () => {
  let mockService: IExchangeRatesService;
  let context: McpToolContext;

  beforeEach(() => {
    context = createMockContext();
    mockService = context.services.exchangeRates;
  });

  describe("input validation", () => {
    it("rejects when date_from is missing", async () => {
      const result = await getExchangeRatesTool.handler({ date_to: "2024-01-31" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when date_to is missing", async () => {
      const result = await getExchangeRatesTool.handler({ date_from: "2024-01-01" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects invalid date format", async () => {
      const result = await getExchangeRatesTool.handler(
        { date_from: "2024/01/01", date_to: "2024-01-31" },
        context,
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when date_from > date_to", async () => {
      const result = await getExchangeRatesTool.handler(
        { date_from: "2024-02-01", date_to: "2024-01-31" },
        context,
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await getExchangeRatesTool.handler(null, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  describe("successful retrieval", () => {
    it("calls exchangeRates.getRates with validated inputs", async () => {
      await getExchangeRatesTool.handler(
        { date_from: "2024-01-01", date_to: "2024-01-31" },
        context,
      );

      expect(mockService.getRates).toHaveBeenCalledWith({
        dateFrom: "2024-01-01",
        dateTo: "2024-01-31",
      });
    });

    it("returns success response with rates and count", async () => {
      const result = await getExchangeRatesTool.handler(
        { date_from: "2024-01-01", date_to: "2024-01-31" },
        context,
      );

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.count).toBe(1);
      expect(parsed.rates).toHaveLength(1);
      expect(parsed.rates[0]).toMatchObject({
        date: "2024-01-15",
        base: "USD",
        quote: "KRW",
        rate: 1320.5,
      });
    });

    it("does not set isError on success", async () => {
      const result = await getExchangeRatesTool.handler(
        { date_from: "2024-01-01", date_to: "2024-01-31" },
        context,
      );
      expect(result.isError).toBeUndefined();
    });

    it("accepts a single-day range", async () => {
      const result = await getExchangeRatesTool.handler(
        { date_from: "2024-01-15", date_to: "2024-01-15" },
        context,
      );
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });
  });

  describe("error handling", () => {
    it("returns isError:true when service throws Error", async () => {
      (mockService.getRates as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("S3 access denied"),
      );

      const result = await getExchangeRatesTool.handler(
        { date_from: "2024-01-01", date_to: "2024-01-31" },
        context,
      );

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toBe("S3 access denied");
    });
  });
});
