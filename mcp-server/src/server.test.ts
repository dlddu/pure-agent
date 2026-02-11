import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { LinearService } from "./services/linear.js";
import { createMcpServer } from "./server.js";

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

function createMockLinearService() {
  return {
    createFeatureRequest: vi.fn().mockResolvedValue({
      issueId: "issue-1",
      issueIdentifier: "PA-1",
      issueUrl: "https://linear.app/issue/PA-1",
    }),
  } as unknown as LinearService;
}

describe("createMcpServer", () => {
  let client: Client;
  let mockLinearService: LinearService;
  let cleanup: () => Promise<void>;

  beforeEach(async () => {
    mockLinearService = createMockLinearService();
    const server = createMcpServer(mockLinearService);
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

    client = new Client({ name: "test-client", version: "1.0.0" });

    await server.connect(serverTransport);
    await client.connect(clientTransport);

    cleanup = async () => {
      await client.close();
      await server.close();
    };
  });

  afterEach(async () => {
    await cleanup();
  });

  describe("listTools", () => {
    it("returns all 3 tools", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(3);
      const names = result.tools.map((t) => t.name);
      expect(names).toContain("request_feature");
      expect(names).toContain("get_export_actions");
      expect(names).toContain("set_export_config");
    });

    it("each tool has name and inputSchema", async () => {
      const result = await client.listTools();

      for (const tool of result.tools) {
        expect(tool.name).toBeDefined();
        expect(tool.inputSchema).toBeDefined();
      }
    });
  });

  describe("callTool routing", () => {
    it("routes request_feature to handleRequestFeature", async () => {
      const result = await client.callTool({
        name: "request_feature",
        arguments: {
          title: "Test feature",
          reason: "Testing routing",
        },
      });

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalled();
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.success).toBe(true);
    });

    it("routes get_export_actions to handleGetExportActions", async () => {
      const result = await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });

      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.actions).toBeDefined();
      expect(parsed.actions).toHaveLength(4);
    });

    it("routes set_export_config to handleSetExportConfig", async () => {
      const result = await client.callTool({
        name: "set_export_config",
        arguments: {
          linear_issue_id: "issue-1",
          summary: "Done",
          action: "none",
        },
      });

      expect(mockWriteFileSync).toHaveBeenCalled();
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      const parsed = JSON.parse(text);
      expect(parsed.success).toBe(true);
    });

    it("returns error for unknown tool name", async () => {
      const result = await client.callTool({
        name: "nonexistent_tool",
        arguments: {},
      });

      expect(result.isError).toBe(true);
      const text = (result.content as Array<{ type: string; text: string }>)[0].text;
      expect(text).toContain("Unknown tool");
      expect(text).toContain("nonexistent_tool");
    });
  });

  describe("request_feature end-to-end via protocol", () => {
    it("valid args -> linearService called -> success response", async () => {
      const result = await client.callTool({
        name: "request_feature",
        arguments: {
          title: "New search tool",
          reason: "Need to search documents",
          priority: "high",
        },
      });

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith({
        title: "New search tool",
        reason: "Need to search documents",
        priority: "high",
      });
      expect(result.isError).toBeFalsy();
    });

    it("invalid args -> error response without calling linearService", async () => {
      const result = await client.callTool({
        name: "request_feature",
        arguments: {
          title: "Hi",
          reason: "Too short title",
        },
      });

      expect(result.isError).toBe(true);
      expect(mockLinearService.createFeatureRequest).not.toHaveBeenCalled();
    });
  });
});
