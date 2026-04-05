import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";
import { createLogger } from "../logger.js";

const log = createLogger("get-issue");

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
    log.info("Fetching issue", { issueId: args.issue_id });
    const issue = await context.services.linear.getIssue(args.issue_id);
    log.info("Issue fetched", { issueId: issue.id, identifier: issue.identifier, title: issue.title, state: issue.state.name });
    return mcpSuccess({ success: true, issue }, { issueId: issue.id });
  },
});
