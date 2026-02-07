import { z } from "zod";

const PrConfigSchema = z.object({
  title: z.string().min(1).max(200),
  body: z.string().max(10000),
  branch: z.string().min(1).max(100),
  base: z.string().max(100).optional().default("main"),
  repo: z.string().max(200).optional(),
});

export const ExportConfigSchema = z.object({
  linear_issue_id: z.string().min(1),
  summary: z.string().min(1).max(10000),
  action: z.enum(["none", "upload_workspace", "report", "create_pr"]),
  report_content: z.string().max(50000).optional(),
  pr: PrConfigSchema.optional(),
});

export type ExportConfig = z.infer<typeof ExportConfigSchema>;
export type PrConfig = z.infer<typeof PrConfigSchema>;
