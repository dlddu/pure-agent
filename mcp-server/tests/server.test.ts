import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createDefaultTools } from "../src/tools/registry.js";
import { sessionCommentHook } from "../src/hooks/post-tool-hooks.js";
import { parseResponseText, createMockContext, createMcpTestClient } from "./test-utils.js";
import type { Client } from "@modelcontextprotocol/sdk/client/index.js";
import type { McpToolContext } from "../src/tools/types.js";

describe("createMcpServer", () => {
  let client: Client;
  let mockContext: McpToolContext;
  let cleanup: () => Promise<void>;

  beforeEach(async () => {
    mockContext = createMockContext({ workDir: "/test/work" });
    ({ client, cleanup } = await createMcpTestClient({
      tools: createDefaultTools(),
      context: mockContext,
      postToolHooks: [sessionCommentHook],
    }));
  });

  afterEach(async () => {
    await cleanup();
  });

  describe("listTools", () => {
    it("returns all 6 tools", async () => {
      const result = await client.listTools();

      expect(result.tools).toHaveLength(6);
      const names = result.tools.map((t) => t.name);
      expect(names).toContain("request_feature");
      expect(names).toContain("get_export_actions");
      expect(names).toContain("set_export_config");
      expect(names).toContain("get_issue");
      expect(names).toContain("get_issue_comments");
    });

    it("each tool has name and inputSchema", async () => {
      const result = await client.listTools();

      for (const tool of result.tools) {
        expect(tool.name).toBeDefined();
        expect(tool.inputSchema).toBeDefined();
      }
    });
  });

  describe("session comment posting", () => {
    it("posts session comment after successful request_feature", async () => {
      (mockContext.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-abc");

      await client.callTool({
        name: "request_feature",
        arguments: { title: "Test feature", reason: "Testing" },
      });

      expect(mockContext.services.session.readSessionId).toHaveBeenCalled();
      expect(mockContext.services.linear.createComment).toHaveBeenCalledWith(
        "issue-1",
        expect.stringContaining("sess-abc"),
      );
    });

    it("posts session comment after successful get_issue", async () => {
      (mockContext.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-abc");

      await client.callTool({
        name: "get_issue",
        arguments: { issue_id: "PA-1" },
      });

      expect(mockContext.services.session.readSessionId).toHaveBeenCalled();
      expect(mockContext.services.linear.createComment).toHaveBeenCalledWith(
        "issue-1",
        expect.stringContaining("sess-abc"),
      );
    });

    it("does not post comment when no session ID", async () => {
      await client.callTool({
        name: "request_feature",
        arguments: { title: "Test feature", reason: "Testing" },
      });

      expect(mockContext.services.session.readSessionId).toHaveBeenCalled();
      expect(mockContext.services.linear.createComment).not.toHaveBeenCalled();
    });

    it("does not post session comment when tool returns error", async () => {
      (mockContext.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-abc");
      (mockContext.services.linear.getIssue as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Not found"),
      );

      await client.callTool({
        name: "get_issue",
        arguments: { issue_id: "PA-999" },
      });

      expect(mockContext.services.session.readSessionId).not.toHaveBeenCalled();
    });

    it("does not post session comment for tools without _meta.issueId", async () => {
      await client.callTool({
        name: "get_export_actions",
        arguments: {},
      });

      expect(mockContext.services.session.readSessionId).not.toHaveBeenCalled();
    });

    it("catches and ignores createComment errors", async () => {
      (mockContext.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-abc");
      (mockContext.services.linear.createComment as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Linear API error"),
      );

      // Should not throw
      const result = await client.callTool({
        name: "request_feature",
        arguments: { title: "Test feature", reason: "Testing" },
      });

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });
  });

});
