import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { SERVER_NAME, SERVER_VERSION } from "./version.js";
import { createLogger } from "./logger.js";
import { runPostToolHooks, type PostToolHook } from "./hooks/post-tool-hooks.js";
import type { McpTool, McpToolContext } from "./tools/types.js";

const log = createLogger("server");

export interface McpServerDeps {
  tools: McpTool[];
  context: McpToolContext;
  postToolHooks?: PostToolHook[];
}

export function createMcpServer(deps: McpServerDeps): McpServer {
  const { tools, context, postToolHooks = [] } = deps;

  const mcpServer = new McpServer(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { capabilities: { tools: {} } },
  );

  for (const tool of tools) {
    mcpServer.registerTool(tool.name, {
      description: tool.description,
      inputSchema: tool.schema,
    }, async (args) => {
      log.info("Tool call started", { toolName: tool.name });
      const start = performance.now();

      const fullResponse = await tool.handler(args, context);
      const { _meta, ...result } = fullResponse;

      await runPostToolHooks(postToolHooks, fullResponse, context);

      const durationMs = Math.round(performance.now() - start);
      log.info("Tool call completed", { toolName: tool.name, durationMs, isError: !!result.isError });

      return result;
    });
  }

  return mcpServer;
}
