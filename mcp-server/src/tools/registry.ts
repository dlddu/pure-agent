import type { McpTool } from "./types.js";
import { requestFeatureTool } from "./request-feature.js";
import { getExportActionsTool } from "./get-export-actions.js";
import { setExportConfigTool } from "./set-export-config.js";
import { getIssueTool } from "./get-issue.js";
import { getIssueCommentsTool } from "./get-issue-comments.js";
import { gitCloneTool } from "./git-clone.js";

export function createDefaultTools(): McpTool[] {
  return [
    requestFeatureTool,
    getExportActionsTool,
    setExportConfigTool,
    getIssueTool,
    getIssueCommentsTool,
    gitCloneTool,
  ];
}
