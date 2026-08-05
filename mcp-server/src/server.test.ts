import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createDefaultTools } from "./tools/registry.js";
import { createMockContext, createMcpTestClient } from "./test-utils.js";
import type { Client } from "@modelcontextprotocol/sdk/client/index.js";
import type { McpToolContext } from "./tools/types.js";

describe("createMcpServer", () => {
  let client: Client;
  let mockContext: McpToolContext;
  let cleanup: () => Promise<void>;

  beforeEach(async () => {
    mockContext = createMockContext({ workDir: "/test/work" });
    ({ client, cleanup } = await createMcpTestClient({
      tools: createDefaultTools(),
      context: mockContext,
    }));
  });

  afterEach(async () => {
    await cleanup();
  });

  describe("listTools", () => {
    it("returns all 5 tools", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(5);
      const names = result.tools.map((t) => t.name);
      expect(names).toContain("get_export_actions");
      expect(names).toContain("set_export_config");
      expect(names).toContain("git_clone");
      expect(names).toContain("web_fetch_get");
      expect(names).toContain("get_exchange_rates");
    });

    it("each tool has name and inputSchema", async () => {
      const result = await client.listTools();

      for (const tool of result.tools) {
        expect(tool.name).toBeDefined();
        expect(tool.inputSchema).toBeDefined();
      }
    });
  });

  describe("registerTool extra forwarding", () => {
    it("passes MCP SDK extra to tool.handler", async () => {
      const capturedExtras: unknown[] = [];

      const spyTool = {
        name: "spy_tool",
        description: "Captures extra from registerTool callback",
        schema: {},
        handler: vi.fn(async (_args: unknown, _context: typeof mockContext, extra?: unknown) => {
          capturedExtras.push(extra);
          return {
            content: [{ type: "text" as const, text: JSON.stringify({ ok: true }) }],
          };
        }),
      };

      const { client: spyClient, cleanup: spyCleanup } = await createMcpTestClient({
        tools: [spyTool as Parameters<typeof createMcpTestClient>[0]["tools"][number]],
        context: mockContext,
      });

      try {
        // MCP SDK의 registerTool 콜백이 extra를 포함하여 호출되고,
        // 그 extra가 tool.handler까지 전달되는지 검증
        await spyClient.callTool({
          name: "spy_tool",
          arguments: {},
        });

        expect(spyTool.handler).toHaveBeenCalled();
        const handlerCall = spyTool.handler.mock.calls[0];
        // extra는 handler의 세 번째 인자로 전달되어야 함
        const passedExtra = handlerCall[2] as { requestId: string; signal: AbortSignal; sessionId: string };
        expect(passedExtra).toBeDefined();
        expect(passedExtra.requestId).toBeDefined();
        expect(passedExtra.signal).toBeDefined();
      } finally {
        await spyCleanup();
      }
    });
  });

});
