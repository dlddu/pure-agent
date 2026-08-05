import type { McpTool } from "./types.js";
import { getExportActionsTool } from "./get-export-actions.js";
import { setExportConfigTool } from "./set-export-config.js";
import { gitCloneTool } from "./git-clone.js";
import { webFetchGetTool } from "./web-fetch-get.js";
import { getExchangeRatesTool } from "./get-exchange-rates.js";

export function createDefaultTools(): McpTool[] {
  return [
    getExportActionsTool,
    setExportConfigTool,
    gitCloneTool,
    webFetchGetTool,
    getExchangeRatesTool,
  ];
}
