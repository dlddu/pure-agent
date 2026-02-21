import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";

const GetIssueCommentsInputSchema = z.object({
  issue_id: z
    .string()
    .min(1, "Issue ID is required")
    .describe("Linear issue ID (UUID) or identifier (e.g., 'PA-42')"),
});

export const getIssueCommentsTool = defineTool({
  name: "get_issue_comments",
  description:
    "Linear 이슈의 모든 코멘트를 조회합니다. 각 코멘트의 본문(마크다운), 작성자, 작성일시를 반환합니다.",
  schema: GetIssueCommentsInputSchema,
  handler: async (args, context) => {
    const comments = await context.services.linear.getIssueComments(args.issue_id);

    return mcpSuccess({ success: true, comments });
  },
});
