import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from "vitest";
import { createDefaultTools } from "../src/tools/registry.js";
import { parseResponseText, createMockContext, getLinearMocks, createMcpTestClient } from "./test-utils.js";
import type { Client } from "@modelcontextprotocol/sdk/client/index.js";

describe("Integration: MCP Protocol End-to-End", () => {
  let client: Client;
  let cleanup: () => Promise<void>;

  const context = createMockContext({ workDir: "/test/work" });
  const linear = getLinearMocks(context);
  let mockWriteFile: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockWriteFile = context.fs.writeFile as ReturnType<typeof vi.fn>;
    linear.createComment.mockResolvedValue({ commentId: "int-comment-new" });
    linear.createFeatureRequest.mockResolvedValue({
      issueId: "int-issue-1",
      issueIdentifier: "INT-1",
      issueUrl: "https://linear.app/issue/INT-1",
    });
    linear.getIssue.mockResolvedValue({
      id: "int-issue-1",
      identifier: "INT-1",
      title: "Integration Test Issue",
      description: "Test description",
      state: { name: "Todo", type: "unstarted" },
      priority: 3,
      priorityLabel: "Medium",
      labels: [],
      assignee: undefined,
      url: "https://linear.app/issue/INT-1",
      createdAt: "2025-01-01T00:00:00.000Z",
      updatedAt: "2025-01-01T00:00:00.000Z",
    });
    linear.getIssueComments.mockResolvedValue([
      {
        id: "int-comment-1",
        body: "Integration test comment",
        user: { id: "user-1", name: "Tester", email: "tester@example.com" },
        createdAt: "2025-01-01T00:00:00.000Z",
        updatedAt: "2025-01-01T00:00:00.000Z",
        url: "https://linear.app/comment/int-comment-1",
      },
    ]);
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
    it("returns all 6 tool definitions with schemas", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(6);

      const toolNames = result.tools.map((t) => t.name);
      expect(toolNames).toContain("request_feature");
      expect(toolNames).toContain("get_export_actions");
      expect(toolNames).toContain("set_export_config");
      expect(toolNames).toContain("get_issue");
      expect(toolNames).toContain("get_issue_comments");
      expect(toolNames).toContain("git_clone");

      for (const tool of result.tools) {
        expect(tool.inputSchema).toBeDefined();
        expect(tool.description).toBeDefined();
      }
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

      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.issue.id).toBe("int-issue-1");
      expect(parsed.issue.identifier).toBe("INT-1");

      expect(linear.createFeatureRequest).toHaveBeenCalledWith({
        title: "Integration test feature",
        reason: "Testing the full pipeline",
        priority: "low",
      });
    });

  });

  describe("tools/call: get_export_actions", () => {
    it("returns the 5 action types", async () => {
      const result = await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });

      expect(result.isError).toBeFalsy();
      const parsed = parseResponseText(result);

      expect(parsed.actions).toHaveLength(5);
      expect(parsed.actions.map((a: { type: string }) => a.type)).toEqual([
        "none",
        "upload_workspace",
        "report",
        "create_pr",
        "continue",
      ]);
    });
  });

  describe("tools/call: set_export_config", () => {
    it("valid config writes file and returns success", async () => {
      mockWriteFile.mockReset().mockResolvedValue(undefined);

      const result = await client.callTool({
        name: "set_export_config",
        arguments: {
          linear_issue_id: "int-issue-1",
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

  describe("tools/call: get_issue", () => {
    it("valid request returns issue data", async () => {
      const result = await client.callTool({
        name: "get_issue",
        arguments: { issue_id: "INT-1" },
      });

      expect(result.isError).toBeFalsy();

      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.issue.id).toBe("int-issue-1");
      expect(parsed.issue.identifier).toBe("INT-1");
      expect(parsed.issue.title).toBe("Integration Test Issue");

      expect(linear.getIssue).toHaveBeenCalledWith("INT-1");
    });

  });

  describe("tools/call: get_issue_comments", () => {
    it("valid request returns comments array", async () => {
      const result = await client.callTool({
        name: "get_issue_comments",
        arguments: { issue_id: "INT-1" },
      });

      expect(result.isError).toBeFalsy();

      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.comments).toHaveLength(1);
      expect(parsed.comments[0].body).toBe("Integration test comment");

      expect(linear.getIssueComments).toHaveBeenCalledWith("INT-1");
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
});
