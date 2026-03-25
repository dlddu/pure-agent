import type { McpTool } from "./types.js";
import { requestFeatureTool } from "./request-feature.js";
import { getExportActionsTool } from "./get-export-actions.js";
import { setExportConfigTool } from "./set-export-config.js";
import { getIssueTool } from "./get-issue.js";
import { getIssueCommentsTool } from "./get-issue-comments.js";
import { gitCloneTool } from "./git-clone.js";
import { webFetchTool } from "./web-fetch.js";

export function createDefaultTools(): McpTool[] {
  return [
    requestFeatureTool,
    getExportActionsTool,
    setExportConfigTool,
    getIssueTool,
    getIssueCommentsTool,
    gitCloneTool,
    webFetchTool,
  ];
}
