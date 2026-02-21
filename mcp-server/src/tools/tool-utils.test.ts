import { describe, it, expect } from "vitest";
import { z } from "zod";
import { withErrorHandling, mcpSuccess, defineTool } from "./tool-utils.js";
import { parseResponseText, createMockContext } from "../test-utils.js";

const mockContext = createMockContext();

describe("mcpSuccess", () => {
  it("returns response without _meta when meta is not provided", () => {
    const result = mcpSuccess({ ok: true });
    expect(result._meta).toBeUndefined();
  });

  it("returns response with _meta when meta is provided", () => {
    const result = mcpSuccess({ ok: true }, { issueId: "issue-1" });
    expect(result._meta).toEqual({ issueId: "issue-1" });
  });
});

describe("withErrorHandling", () => {
  it("returns the handler result on success", async () => {
    const handler = withErrorHandling(() => mcpSuccess({ ok: true }));
    const result = await handler({}, mockContext);
    expect(result.isError).toBeUndefined();
    const parsed = parseResponseText(result);
    expect(parsed.ok).toBe(true);
  });

  it("catches Error and returns mcpError", async () => {
    const ctx = createMockContext();
    const handler = withErrorHandling(() => {
      throw new Error("boom");
    });
    const result = await handler({}, ctx);
    expect(result.isError).toBe(true);
    const parsed = parseResponseText(result);
    expect(parsed.error).toBe("boom");
    expect(ctx.logger.error).toHaveBeenCalledWith("Tool handler error", expect.objectContaining({ error: "boom" }));
  });

  it("catches non-Error and returns 'Unknown error occurred'", async () => {
    const ctx = createMockContext();
    const handler = withErrorHandling(() => {
      throw "string error";
    });
    const result = await handler({}, ctx);
    expect(result.isError).toBe(true);
    const parsed = parseResponseText(result);
    expect(parsed.error).toBe("Unknown error occurred");
    expect(ctx.logger.error).toHaveBeenCalledWith("Tool handler error", expect.objectContaining({ error: "Unknown error occurred" }));
  });

  it("handles async handlers that reject", async () => {
    const handler = withErrorHandling(async () => {
      throw new Error("async boom");
    });
    const result = await handler({}, mockContext);
    expect(result.isError).toBe(true);
    const parsed = parseResponseText(result);
    expect(parsed.error).toBe("async boom");
  });
});

describe("defineTool", () => {
  const testSchema = z.object({
    name: z.string().min(1),
    count: z.number().optional().default(1),
  });

  const tool = defineTool({
    name: "test_tool",
    description: "A test tool",
    schema: testSchema,
    handler: (args, _context) => {
      return mcpSuccess({ received: args.name, count: args.count });
    },
  });

  it("returns McpTool with correct name and description", () => {
    expect(tool.name).toBe("test_tool");
    expect(tool.description).toBe("A test tool");
  });

  it("stores the original Zod schema", () => {
    expect(tool.schema).toBeDefined();
    const parsed = tool.schema.safeParse({ name: "test" });
    expect(parsed.success).toBe(true);
    const invalid = tool.schema.safeParse({});
    expect(invalid.success).toBe(false);
  });

  it("handler receives parsed and typed args", async () => {
    const result = await tool.handler({ name: "hello" }, mockContext);
    const parsed = parseResponseText(result);
    expect(parsed.received).toBe("hello");
    expect(parsed.count).toBe(1); // default applied by Zod
  });

  it("returns validation error for invalid args", async () => {
    const result = await tool.handler({ name: "" }, mockContext);
    expect(result.isError).toBe(true);
    const parsed = parseResponseText(result);
    expect(parsed.success).toBe(false);
    expect(parsed.error).toContain("Validation failed");
  });

  it("returns validation error for missing required field", async () => {
    const result = await tool.handler({}, mockContext);
    expect(result.isError).toBe(true);
  });

  it("catches async errors from handler", async () => {
    const asyncTool = defineTool({
      name: "async_fail",
      description: "fails async",
      schema: z.object({}),
      handler: async () => {
        throw new Error("async failure");
      },
    });
    const result = await asyncTool.handler({}, mockContext);
    expect(result.isError).toBe(true);
    const parsed = parseResponseText(result);
    expect(parsed.error).toBe("async failure");
  });
});
