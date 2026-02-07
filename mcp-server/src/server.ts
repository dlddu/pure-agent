import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { REQUEST_FEATURE_TOOL, handleRequestFeature } from "./tools/request-feature.js";
import {
  GET_EXPORT_ACTIONS_TOOL,
  SET_EXPORT_CONFIG_TOOL,
  handleGetExportActions,
  handleSetExportConfig,
} from "./tools/export-actions.js";
import type { LinearService } from "./services/linear.js";

export function createMcpServer(linearService: LinearService): Server {
  const server = new Server(
    {
      name: "pure-agent-mcp-server",
      version: "1.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
      tools: [REQUEST_FEATURE_TOOL, GET_EXPORT_ACTIONS_TOOL, SET_EXPORT_CONFIG_TOOL],
    };
  });

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    if (name === "request_feature") {
      return handleRequestFeature(linearService, args);
    }

    if (name === "get_export_actions") {
      return handleGetExportActions();
    }

    if (name === "set_export_config") {
      return handleSetExportConfig(args);
    }

    return {
      content: [
        {
          type: "text",
          text: `Unknown tool: ${name}`,
        },
      ],
      isError: true,
    };
  });

  return server;
}
