import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer } from "../server.js";
import type { LinearService } from "../services/linear.js";

const { mockWriteFileSync } = vi.hoisted(() => ({
  mockWriteFileSync: vi.fn(),
}));

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    writeFileSync: mockWriteFileSync,
  };
});

describe("Integration: MCP Protocol End-to-End", () => {
  let client: Client;
  let cleanup: () => Promise<void>;

  const mockCreateFeatureRequest = vi.fn();
  const mockLinearService = {
    createFeatureRequest: mockCreateFeatureRequest,
  } as unknown as LinearService;

  beforeEach(() => {
    mockCreateFeatureRequest.mockResolvedValue({
      issueId: "int-issue-1",
      issueIdentifier: "INT-1",
      issueUrl: "https://linear.app/issue/INT-1",
    });
  });

  beforeAll(async () => {
    const server = createMcpServer(mockLinearService);
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

    client = new Client({ name: "integration-test", version: "1.0.0" });

    await server.connect(serverTransport);
    await client.connect(clientTransport);

    cleanup = async () => {
      await client.close();
      await server.close();
    };
  });

  afterAll(async () => {
    await cleanup();
  });

  describe("tools/list", () => {
    it("returns all 3 tool definitions with schemas", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(3);

      const requestFeature = result.tools.find((t) => t.name === "request_feature");
      expect(requestFeature).toBeDefined();
      expect(requestFeature!.inputSchema.properties).toHaveProperty("title");
      expect(requestFeature!.inputSchema.properties).toHaveProperty("reason");

      const getExportActions = result.tools.find((t) => t.name === "get_export_actions");
      expect(getExportActions).toBeDefined();

      const setExportConfig = result.tools.find((t) => t.name === "set_export_config");
      expect(setExportConfig).toBeDefined();
      expect(setExportConfig!.inputSchema.properties).toHaveProperty("linear_issue_id");
    });
  });

  describe("tools/call: request_feature", () => {
    it("valid request creates Linear issue and returns success", async () => {
      const result = await client.callTool({
        name: "request_feature",
        arguments: {
          title: "Integration test feature",
          reason: "Testing the full pipeline",
          priority: "low",
        },
      });

      expect(result.isError).toBeFalsy();

      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);

      expect(parsed.success).toBe(true);
      expect(parsed.issue.id).toBe("int-issue-1");
      expect(parsed.issue.identifier).toBe("INT-1");

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith({
        title: "Integration test feature",
        reason: "Testing the full pipeline",
        priority: "low",
      });
    });

    it("invalid title returns validation error", async () => {
      const result = await client.callTool({
        name: "request_feature",
        arguments: {
          title: "abc",
          reason: "Too short",
        },
      });

      expect(result.isError).toBe(true);
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.success).toBe(false);
    });
  });

  describe("tools/call: get_export_actions", () => {
    it("returns the 4 action types", async () => {
      const result = await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });

      expect(result.isError).toBeFalsy();
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);

      expect(parsed.actions).toHaveLength(4);
      expect(parsed.actions.map((a: { type: string }) => a.type)).toEqual([
        "none",
        "upload_workspace",
        "report",
        "create_pr",
      ]);
    });
  });

  describe("tools/call: set_export_config", () => {
    it("valid config writes file and returns success", async () => {
      mockWriteFileSync.mockReset();

      const result = await client.callTool({
        name: "set_export_config",
        arguments: {
          linear_issue_id: "int-issue-1",
          summary: "Integration test completed",
          action: "none",
        },
      });

      expect(result.isError).toBeFalsy();
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.success).toBe(true);
      expect(mockWriteFileSync).toHaveBeenCalledTimes(1);
    });

    it("action=report without report_content returns business rule error", async () => {
      const result = await client.callTool({
        name: "set_export_config",
        arguments: {
          linear_issue_id: "int-issue-1",
          summary: "Report test",
          action: "report",
        },
      });

      expect(result.isError).toBe(true);
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.error).toContain("report_content");
    });
  });

  describe("tools/call: unknown tool", () => {
    it('returns "Unknown tool" error', async () => {
      const result = await client.callTool({
        name: "does_not_exist",
        arguments: {},
      });

      expect(result.isError).toBe(true);
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      expect(text).toContain("Unknown tool");
      expect(text).toContain("does_not_exist");
    });
  });
});
