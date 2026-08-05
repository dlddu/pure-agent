import { z } from "zod";
import { join } from "node:path";
import { defineTool, mcpSuccess } from "./tool-utils.js";
import {
  EXPORT_ACTION_TYPES,
  EXPORT_CONFIG_FILENAME,
  EXCLUSIVE_ACTIONS,
  ACTION_REQUIREMENTS,
  PrConfigSchema,
  MAX_SUMMARY_LENGTH,
} from "./export-constants.js";

const SetExportConfigInputSchema = z.object({
  summary: z
    .string()
    .min(1)
    .max(MAX_SUMMARY_LENGTH)
    .describe("작업 요약. export 결과에 항상 기록됩니다."),
  actions: z
    .array(z.enum(EXPORT_ACTION_TYPES))
    .min(1)
    .describe("수행할 export action 타입 배열. 'none'은 단독으로만 사용 가능."),
  pr: PrConfigSchema.optional().describe("PR 설정 (actions에 'create_pr' 포함 시 필수)"),
}).superRefine((data, ctx) => {
  // Exclusive actions (none) must be alone
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

  // Conditional field requirements (driven by ACTION_REQUIREMENTS)
  for (const [action, { field }] of Object.entries(ACTION_REQUIREMENTS)) {
    if (
      data.actions.includes(action as (typeof EXPORT_ACTION_TYPES)[number]) &&
      !data[field as keyof typeof data]
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `${field} is required when actions include '${action}'`,
        path: [field],
      });
    }
  }
});

export const setExportConfigTool = defineTool({
  name: "set_export_config",
  description:
    "작업 완료 후 export 설정을 저장합니다. 이 설정에 따라 선택한 action이 수행됩니다. 반드시 작업 완료 시점에 호출하세요.",
  schema: SetExportConfigInputSchema,
  handler: async (args, context) => {
    const exportConfigPath = join(context.workDir, EXPORT_CONFIG_FILENAME);
    await context.io.fs.writeFile(exportConfigPath, JSON.stringify(args, null, 2), "utf-8");

    return mcpSuccess({
      success: true,
      message: `Export config saved. Actions [${args.actions.join(", ")}] will be executed after the cycle completes.`,
      config_path: exportConfigPath,
    });
  },
});
