import { describe, it, expect, vi, beforeEach } from "vitest";
import { parseResponseText, createMockContext } from "../test-utils.js";
import { setExportConfigTool } from "../../src/tools/set-export-config.js";
import type { McpToolContext } from "../../src/tools/types.js";

let context: McpToolContext;
let mockWriteFile: ReturnType<typeof vi.fn>;

describe("setExportConfigTool", () => {
  beforeEach(() => {
    context = createMockContext({ workDir: "/test/work" });
    mockWriteFile = context.fs.writeFile as ReturnType<typeof vi.fn>;
  });

  const validArgs = {
    linear_issue_id: "issue-123",
    summary: "Task completed successfully",
    actions: ["none"],
  };

  describe("input validation", () => {
    it("accepts when linear_issue_id is missing", async () => {
      const result = await setExportConfigTool.handler({
        summary: "summary",
        actions: ["none"],
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("rejects when summary is missing", async () => {
      const result = await setExportConfigTool.handler({
        linear_issue_id: "id",
        actions: ["none"],
      }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects when actions contain invalid value", async () => {
      const result = await setExportConfigTool.handler({
        linear_issue_id: "id",
        summary: "summary",
        actions: ["invalid_action"],
      }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects when actions is empty", async () => {
      const result = await setExportConfigTool.handler({
        linear_issue_id: "id",
        summary: "summary",
        actions: [],
      }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects when summary exceeds 10000 characters", async () => {
      const result = await setExportConfigTool.handler({
        linear_issue_id: "id",
        summary: "x".repeat(10001),
        actions: ["none"],
      }, context);
      expect(result.isError).toBe(true);
    });
  });

  describe("business rules", () => {
    it("rejects report without report_content", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["report"],
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("report_content");
    });

    it("rejects create_pr without pr config", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["create_pr"],
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("pr is required when actions include 'create_pr'");
    });

    it("accepts report with report_content provided", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["report"],
        report_content: "# Analysis Report\n\nFindings...",
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts create_pr with valid pr config", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["create_pr"],
        pr: {
          title: "Add feature X",
          body: "This PR adds feature X",
          branch: "feature/x",
          repo: "org/repo",
          repo_path: "repo",
        },
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts none without optional fields", async () => {
      const result = await setExportConfigTool.handler(validArgs, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts upload_workspace without optional fields", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["upload_workspace"],
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts continue action", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["continue"],
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts multiple combinable actions", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["upload_workspace", "report"],
        report_content: "content",
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("rejects none combined with other actions", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["none", "upload_workspace"],
      }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects continue combined with other actions", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["continue", "report"],
        report_content: "content",
      }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects upload_workspace without linear_issue_id", async () => {
      const result = await setExportConfigTool.handler({
        summary: "summary",
        actions: ["upload_workspace"],
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("linear_issue_id");
    });

    it("rejects report without linear_issue_id", async () => {
      const result = await setExportConfigTool.handler({
        summary: "summary",
        actions: ["report"],
        report_content: "content",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("linear_issue_id");
    });

    it("accepts none without linear_issue_id", async () => {
      const result = await setExportConfigTool.handler({
        summary: "summary",
        actions: ["none"],
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts continue without linear_issue_id", async () => {
      const result = await setExportConfigTool.handler({
        summary: "summary",
        actions: ["continue"],
      }, context);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("rejects duplicate actions", async () => {
      const result = await setExportConfigTool.handler({
        ...validArgs,
        actions: ["upload_workspace", "upload_workspace"],
      }, context);
      expect(result.isError).toBe(true);
    });
  });

  describe("file writing", () => {
    it("writes validated config to export_config.json", async () => {
      await setExportConfigTool.handler(validArgs, context);

      expect(mockWriteFile).toHaveBeenCalledTimes(1);
      const [filePath, content, encoding] = mockWriteFile.mock.calls[0];
      expect(filePath).toContain("export_config.json");
      expect(encoding).toBe("utf-8");

      const written = JSON.parse(content);
      expect(written.linear_issue_id).toBe("issue-123");
      expect(written.summary).toBe("Task completed successfully");
      expect(written.actions).toEqual(["none"]);
    });

    it('applies pr.base default value "main" in written config', async () => {
      await setExportConfigTool.handler({
        ...validArgs,
        actions: ["create_pr"],
        pr: {
          title: "PR title",
          body: "PR body",
          branch: "feature/branch",
          repo: "org/repo",
          repo_path: "repo",
        },
      }, context);

      const written = JSON.parse(mockWriteFile.mock.calls[0][1]);
      expect(written.pr.base).toBe("main");
    });

    it("returns error when writeFile rejects", async () => {
      mockWriteFile.mockRejectedValue(new Error("EACCES: permission denied"));

      const result = await setExportConfigTool.handler(validArgs, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("EACCES");
    });
  });

  describe("response shape", () => {
    it("returns config_path and action names in success message", async () => {
      const result = await setExportConfigTool.handler(validArgs, context);
      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.config_path).toContain("export_config.json");
      expect(parsed.message).toContain("none");
    });
  });
});
