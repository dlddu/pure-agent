import { z } from "zod";
import {
  EXPORT_ACTIONS,
  EXCLUSIVE_ACTIONS,
  ACTIONS_REQUIRING_ISSUE,
  MAX_PR_TITLE_LENGTH,
  MAX_PR_BODY_LENGTH,
  MAX_PR_BRANCH_LENGTH,
  MAX_PR_REPO_LENGTH,
  MAX_PR_REPO_PATH_LENGTH,
  MAX_SUMMARY_LENGTH,
  MAX_REPORT_CONTENT_LENGTH,
} from "./constants.js";

const PrConfigSchema = z.object({
  title: z.string().min(1).max(MAX_PR_TITLE_LENGTH),
  body: z.string().max(MAX_PR_BODY_LENGTH),
  branch: z.string().min(1).max(MAX_PR_BRANCH_LENGTH),
  base: z.string().max(MAX_PR_BRANCH_LENGTH).optional().default("main"),
  repo: z.string().min(1).max(MAX_PR_REPO_LENGTH),
  repo_path: z.string().min(1).max(MAX_PR_REPO_PATH_LENGTH),
});

export const ExportConfigSchema = z.object({
  linear_issue_id: z.string().min(1).optional(),
  summary: z.string().min(1).max(MAX_SUMMARY_LENGTH),
  actions: z.array(z.enum(EXPORT_ACTIONS)).min(1),
  report_content: z.string().max(MAX_REPORT_CONTENT_LENGTH).optional(),
  pr: PrConfigSchema.optional(),
}).superRefine((data, ctx) => {
  // Exclusive actions (none, continue) must be alone
  for (const action of data.actions) {
    if (EXCLUSIVE_ACTIONS.has(action) && data.actions.length > 1) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Action '${action}' must be the only action when present`,
        path: ["actions"],
      });
      return;
    }
  }

  // No duplicate actions
  if (new Set(data.actions).size !== data.actions.length) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Duplicate actions are not allowed",
      path: ["actions"],
    });
  }

  // Actions that require linear_issue_id
  if (
    data.actions.some((a) => ACTIONS_REQUIRING_ISSUE.has(a)) &&
    !data.linear_issue_id
  ) {
    const required = data.actions.filter((a) => ACTIONS_REQUIRING_ISSUE.has(a));
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: `linear_issue_id is required when actions include ${required.map((a) => `'${a}'`).join(", ")}`,
      path: ["linear_issue_id"],
    });
  }

  // report requires report_content
  if (data.actions.includes("report") && !data.report_content) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "report_content is required when actions include 'report'",
      path: ["report_content"],
    });
  }

  // create_pr requires pr config
  if (data.actions.includes("create_pr") && !data.pr) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "pr config is required when actions include 'create_pr'",
      path: ["pr"],
    });
  }
});

export type ExportConfig = z.infer<typeof ExportConfigSchema>;
export type PrConfig = z.infer<typeof PrConfigSchema>;
