import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { SERVER_NAME, SERVER_VERSION } from "./version.js";
import { createLogger } from "./logger.js";
import type { McpTool, McpToolContext, McpToolExtra } from "./tools/types.js";

const log = createLogger("server");

export interface McpServerDeps {
  tools: McpTool[];
  context: McpToolContext;
}

export function createMcpServer(deps: McpServerDeps): McpServer {
  const { tools, context } = deps;

  const mcpServer = new McpServer(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { capabilities: { tools: {} } },
  );

  for (const tool of tools) {
    mcpServer.registerTool(tool.name, {
      description: tool.description,
      inputSchema: tool.schema,
    }, async (args, extra) => {
      log.info("Tool call started", { toolName: tool.name, args });
      const start = performance.now();

      const mcpExtra: McpToolExtra = {
        requestId: extra.requestId,
        sessionId: extra.sessionId,
        signal: extra.signal,
      };
      const result = await tool.handler(args, context, mcpExtra);

      const durationMs = Math.round(performance.now() - start);
      log.info("Tool call completed", { toolName: tool.name, durationMs, isError: !!result.isError });

      return result;
    });
  }

  return mcpServer;
}
