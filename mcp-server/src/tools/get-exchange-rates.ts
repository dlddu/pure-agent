import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";
import { createLogger } from "../logger.js";

const log = createLogger("get-exchange-rates");

const DateStr = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Date must be in YYYY-MM-DD format");

const GetExchangeRatesInputSchema = z
  .object({
    date_from: DateStr.describe("시작 날짜 (포함, YYYY-MM-DD)"),
    date_to: DateStr.describe("종료 날짜 (포함, YYYY-MM-DD)"),
  })
  .refine((v) => v.date_from <= v.date_to, {
    message: "date_from must be <= date_to",
    path: ["date_from"],
  });

export const getExchangeRatesTool = defineTool({
  name: "get_exchange_rates",
  description:
    "지정된 기간의 환율 데이터를 S3(Parquet)에서 조회합니다. " +
    "date_from과 date_to(모두 포함, YYYY-MM-DD)를 받아 월별 파티션을 병합해 반환합니다. " +
    "최대 12개월 범위까지 지원합니다.",
  schema: GetExchangeRatesInputSchema,
  handler: async (args, context) => {
    log.info("Fetching exchange rates", {
      dateFrom: args.date_from,
      dateTo: args.date_to,
    });
    const rates = await context.services.exchangeRates.getRates({
      dateFrom: args.date_from,
      dateTo: args.date_to,
    });
    log.info("Exchange rates fetched", { count: rates.length });
    return mcpSuccess({ success: true, count: rates.length, rates });
  },
});
