import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";

const GetIssueInputSchema = z.object({
  issue_id: z
    .string()
    .min(1, "Issue ID is required")
    .describe("Linear issue ID (UUID) or identifier (e.g., 'PA-42')"),
});

export const getIssueTool = defineTool({
  name: "get_issue",
  description:
    "Linear 이슈를 ID 또는 식별자로 조회합니다. 이슈의 제목, 설명, 상태, 우선순위, 라벨, 담당자 등의 메타데이터를 반환합니다.",
  schema: GetIssueInputSchema,
  handler: async (args, context) => {
    const issue = await context.services.linear.getIssue(args.issue_id);
    return mcpSuccess({ success: true, issue }, { issueId: issue.id });
  },
});
