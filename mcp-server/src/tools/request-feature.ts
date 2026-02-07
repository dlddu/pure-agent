import { z } from "zod";
import type { LinearService } from "../services/linear.js";

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

export const REQUEST_FEATURE_TOOL = {
  name: "request_feature",
  description:
    "Request the developer to add or extend MCP server capabilities. Use this when you cannot complete a task due to missing or insufficient tools, so that the functionality can be available in the next session.",
  inputSchema: {
    type: "object" as const,
    properties: {
      title: {
        type: "string",
        description: "Title of the feature request",
        minLength: 5,
        maxLength: 200,
      },
      reason: {
        type: "string",
        description: "Why this feature is needed",
        maxLength: 10000,
      },
      priority: {
        type: "string",
        enum: ["urgent", "high", "medium", "low", "none"],
        description: "Priority level for the feature request",
        default: "medium",
      },
    },
    required: ["title", "reason"],
  },
};

export async function handleRequestFeature(
  linearService: LinearService,
  args: unknown
): Promise<{ content: Array<{ type: "text"; text: string }>; isError?: boolean }> {
  try {
    const validated = RequestFeatureInputSchema.parse(args);

    const result = await linearService.createFeatureRequest({
      title: validated.title,
      reason: validated.reason,
      priority: validated.priority,
    });

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              success: true,
              message: "Feature request created successfully",
              issue: {
                id: result.issueId,
                identifier: result.issueIdentifier,
                url: result.issueUrl,
              },
            },
            null,
            2
          ),
        },
      ],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(
            {
              success: false,
              error: errorMessage,
            },
            null,
            2
          ),
        },
      ],
      isError: true,
    };
  }
}
