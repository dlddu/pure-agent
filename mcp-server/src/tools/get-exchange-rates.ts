import { z } from "zod";
import { basename, join } from "node:path";
import { defineTool, mcpSuccess, mcpError } from "./tool-utils.js";

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DATE_PARTITION_RE = /date=(\d{4}-\d{2}-\d{2})\//;

const GetExchangeRatesInputSchema = z
  .object({
    date: z
      .string()
      .regex(DATE_RE, "date must be YYYY-MM-DD")
      .optional()
      .describe("단일 날짜 조회 (YYYY-MM-DD). start_date/end_date와 함께 쓸 수 없음."),
    start_date: z
      .string()
      .regex(DATE_RE, "start_date must be YYYY-MM-DD")
      .optional()
      .describe("범위 조회 시작일 (YYYY-MM-DD, 포함). end_date와 함께 지정."),
    end_date: z
      .string()
      .regex(DATE_RE, "end_date must be YYYY-MM-DD")
      .optional()
      .describe("범위 조회 종료일 (YYYY-MM-DD, 포함). start_date와 함께 지정."),
  })
  .superRefine((data, ctx) => {
    const hasSingle = !!data.date;
    const hasRange = !!data.start_date || !!data.end_date;
    if (hasSingle && hasRange) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Provide either 'date' OR 'start_date'+'end_date', not both",
        path: ["date"],
      });
      return;
    }
    if (!hasSingle && !hasRange) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Must provide 'date' or both 'start_date' and 'end_date'",
        path: ["date"],
      });
      return;
    }
    if (hasRange && (!data.start_date || !data.end_date)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Both 'start_date' and 'end_date' are required for range query",
        path: ["start_date"],
      });
      return;
    }
    if (data.start_date && data.end_date && data.start_date > data.end_date) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "start_date must be <= end_date",
        path: ["start_date"],
      });
    }
  });

export const getExchangeRatesTool = defineTool({
  name: "get_exchange_rates",
  description:
    "S3 gold 레이어(gold/exchange_rates/date=YYYY-MM-DD/)에서 환율 데이터 파일을 다운로드하여 로컬 파일 경로로 반환합니다. 단일 날짜(date) 또는 시작/종료 범위(start_date, end_date)로 조회할 수 있습니다.",
  schema: GetExchangeRatesInputSchema,
  handler: async (args, context) => {
    const startDate = args.date ?? args.start_date!;
    const endDate = args.date ?? args.end_date!;
    const isRange = !args.date;

    const dirName = isRange ? `${startDate}_${endDate}` : startDate;
    const localDir = join(context.workDir, "exchange_rates", dirName);

    let keys: string[];
    try {
      keys = await context.services.exchangeRates.listByDateRange(startDate, endDate);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      return mcpError(`Failed to list exchange rate objects: ${message}`);
    }

    if (keys.length === 0) {
      return mcpError(
        `No exchange rate files found for ${isRange ? `${startDate}..${endDate}` : startDate} under gold/exchange_rates/`,
      );
    }

    await context.io.fs.mkdir(localDir, { recursive: true });

    const files: Array<{ s3_key: string; local_path: string; size_bytes: number }> = [];
    for (const key of keys) {
      const bytes = await context.services.exchangeRates.getObject(key);
      const fileName = basename(key);

      let targetDir = localDir;
      if (isRange) {
        const match = DATE_PARTITION_RE.exec(key);
        if (match) {
          targetDir = join(localDir, match[1]);
          await context.io.fs.mkdir(targetDir, { recursive: true });
        }
      }

      const localPath = join(targetDir, fileName);
      await context.io.fs.writeBinaryFile(localPath, bytes);
      files.push({ s3_key: key, local_path: localPath, size_bytes: bytes.byteLength });
    }

    context.logger.info("Downloaded exchange rate files", {
      count: files.length,
      directory: localDir,
    });

    return mcpSuccess({
      success: true,
      query: args.date ? { date: args.date } : { start_date: args.start_date, end_date: args.end_date },
      directory: localDir,
      files,
      count: files.length,
    });
  },
});
