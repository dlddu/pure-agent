import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";

const RequestFeatureInputSchema = z.object({
  title: z
    .string()
    .min(5, "Title must be at least 5 characters")
    .max(200, "Title must be at most 200 characters")
    .describe("Title of the feature request"),

  reason: z
    .string()
    .min(1, "Reason is required")
    .max(10000, "Reason must be at most 10000 characters")
    .describe("Why this feature is needed"),

  priority: z
    .enum(["urgent", "high", "medium", "low", "none"])
    .optional()
    .default("medium")
    .describe("Priority level for the feature request"),
});

export const requestFeatureTool = defineTool({
  name: "request_feature",
  description:
    "MCP 서버 기능 추가 또는 확장을 개발자에게 요청합니다. 도구가 부족하거나 없어서 작업을 완료할 수 없을 때 사용하세요. 다음 세션에서 해당 기능을 사용할 수 있게 됩니다.",
  schema: RequestFeatureInputSchema,
  handler: async (args, context) => {
    const result = await context.services.linear.createFeatureRequest({
      title: args.title,
      reason: args.reason,
      priority: args.priority,
    });

    return mcpSuccess(
      {
        success: true,
        message: "Feature request created successfully",
        issue: {
          id: result.issueId,
          identifier: result.issueIdentifier,
          url: result.issueUrl,
        },
      },
      { issueId: result.issueId },
    );
  },
});
