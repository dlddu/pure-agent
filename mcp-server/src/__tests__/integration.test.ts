import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from "vitest";
import { createDefaultTools } from "../tools/registry.js";
import { parseResponseText, createMockContext, createMcpTestClient } from "../test-utils.js";
import type { Client } from "@modelcontextprotocol/sdk/client/index.js";

describe("Integration: MCP Protocol End-to-End", () => {
  let client: Client;
  let cleanup: () => Promise<void>;

  const context = createMockContext({ workDir: "/test/work" });
  let mockWriteFile: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockWriteFile = context.io.fs.writeFile as ReturnType<typeof vi.fn>;
  });

  beforeAll(async () => {
    ({ client, cleanup } = await createMcpTestClient({
      tools: createDefaultTools(),
      context,
    }));
  });

  afterAll(async () => {
    await cleanup();
  });

  describe("tools/list", () => {
    it("returns all 5 tool definitions with schemas", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(5);

      const toolNames = result.tools.map((t) => t.name);
      expect(toolNames).toContain("get_export_actions");
      expect(toolNames).toContain("set_export_config");
      expect(toolNames).toContain("git_clone");
      expect(toolNames).toContain("web_fetch_get");
      expect(toolNames).toContain("get_exchange_rates");

      for (const tool of result.tools) {
        expect(tool.inputSchema).toBeDefined();
        expect(tool.description).toBeDefined();
      }
    });
  });

  describe("tools/call: get_export_actions", () => {
    it("returns the 2 action types", async () => {
      const result = await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });

      expect(result.isError).toBeFalsy();
      const parsed = parseResponseText(result);

      expect(parsed.actions).toHaveLength(2);
      expect(parsed.actions.map((a: { type: string }) => a.type)).toEqual([
        "none",
        "create_pr",
      ]);
    });
  });

  describe("tools/call: set_export_config", () => {
    it("valid config writes file and returns success", async () => {
      mockWriteFile.mockReset().mockResolvedValue(undefined);

      const result = await client.callTool({
        name: "set_export_config",
        arguments: {
          summary: "Integration test completed",
          actions: ["none"],
        },
      });

      expect(result.isError).toBeFalsy();
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(mockWriteFile).toHaveBeenCalledTimes(1);
    });

  });

  describe("tools/call: unknown tool", () => {
    it('returns "not found" error', async () => {
      const result = await client.callTool({
        name: "does_not_exist",
        arguments: {},
      });

      expect(result.isError).toBe(true);
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      expect(text).toContain("does_not_exist");
      expect(text).toContain("not found");
    });
  });

  describe("tools/call: web_fetch_get", () => {
    it("performs HTTP fetch and returns success response when approved", async () => {
      // Mock the gatekeeper to approve the request
      const mockApproval = context.services.gatekeeper.requestApproval as ReturnType<typeof vi.fn>;
      mockApproval.mockResolvedValue({ status: "APPROVED", requestId: "req-int-1" });

      // Mock session to return a session id
      const mockSession = context.services.session.readSessionId as ReturnType<typeof vi.fn>;
      mockSession.mockResolvedValue({ sessionId: "int-session-id", source: "agent" });

      const mockFetch = vi.fn().mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("application/json") },
        text: vi.fn().mockResolvedValue('{"message":"hello"}'),
      });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (context.io as any).fetch = mockFetch;

      const result = await client.callTool({
        name: "web_fetch_get",
        arguments: {
          url: "https://api.example.com/hello",
        },
      });

      expect(result.isError).toBeFalsy();

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.status).toBe(200);
      expect(parsed.body).toContain("hello");

      expect(mockApproval).toHaveBeenCalled();
      expect(mockFetch).toHaveBeenCalledWith(
        "https://api.example.com/hello",
        expect.objectContaining({ method: "GET" }),
      );
    });
  });

  describe("extra forwarding", () => {
    it("existing tools work with new signature (extra is ignored)", async () => {
      // 새 시그니처(extra 파라미터 추가) 도입 후에도 기존 도구들이
      // extra를 무시하고 정상적으로 동작하는지 end-to-end로 검증

      // get_export_actions 도구 호출 — extra는 MCP SDK가 자동으로 전달
      const actionsResult = await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });
      expect(actionsResult.isError).toBeFalsy();
      const actionsParsed = parseResponseText(actionsResult);
      expect(actionsParsed.success).toBe(true);

      // set_export_config 도구 호출 — extra는 MCP SDK가 자동으로 전달
      mockWriteFile.mockReset().mockResolvedValue(undefined);
      const configResult = await client.callTool({
        name: "set_export_config",
        arguments: {
          summary: "Extra compat test",
          actions: ["none"],
        },
      });
      expect(configResult.isError).toBeFalsy();
      const configParsed = parseResponseText(configResult);
      expect(configParsed.success).toBe(true);
    });
  });
});
