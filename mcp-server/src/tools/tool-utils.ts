import { type z, ZodError } from "zod";
import type { McpToolMeta, McpToolResponse, McpToolContext, McpTool } from "./types.js";

export function mcpSuccess(data: unknown, meta?: McpToolMeta): McpToolResponse {
  return {
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    ...(meta && { _meta: meta }),
  };
}

export function mcpError(errorMessage: string): McpToolResponse {
  return {
    content: [{ type: "text", text: JSON.stringify({ success: false, error: errorMessage }) }],
    isError: true,
  };
}

export function withErrorHandling(
  handler: (args: unknown, context: McpToolContext) => Promise<McpToolResponse> | McpToolResponse,
): (args: unknown, context: McpToolContext) => Promise<McpToolResponse> {
  return async (args: unknown, context: McpToolContext): Promise<McpToolResponse> => {
    try {
      return await handler(args, context);
    } catch (error) {
      if (error instanceof ZodError) {
        const details = error.issues.map(i => `${i.path.join(".")}: ${i.message}`).join("; ");
        return mcpError(`Validation failed: ${details}`);
      }
      const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";
      context.logger.error("Tool handler error", {
        error: errorMessage,
        stack: error instanceof Error ? error.stack : undefined,
      });
      return mcpError(errorMessage);
    }
  };
}

export function defineTool<T extends z.ZodType>(def: {
  name: string;
  description: string;
  schema: T;
  handler: (args: z.infer<T>, context: McpToolContext) => Promise<McpToolResponse> | McpToolResponse;
}): McpTool {
  return {
    name: def.name,
    description: def.description,
    schema: def.schema,
    handler: withErrorHandling(async (args: unknown, context: McpToolContext) => {
      const validated = def.schema.parse(args);
      return def.handler(validated, context);
    }),
  };
}
