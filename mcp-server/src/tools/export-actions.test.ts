import { describe, it, expect, vi, beforeEach } from "vitest";

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

import { handleGetExportActions, handleSetExportConfig } from "./export-actions.js";

function parseResponseText(result: { content: Array<{ type: string; text: string }> }) {
  return JSON.parse(result.content[0].text);
}

describe("handleGetExportActions", () => {
  it("returns all 4 export action types", () => {
    const result = handleGetExportActions();
    const parsed = parseResponseText(result);

    expect(parsed.actions).toHaveLength(4);
    const types = parsed.actions.map((a: { type: string }) => a.type);
    expect(types).toEqual(["none", "upload_workspace", "report", "create_pr"]);
  });

  it("does not set isError on the response", () => {
    const result = handleGetExportActions();
    expect(result).not.toHaveProperty("isError");
  });

  it("includes correct required_fields for each action", () => {
    const result = handleGetExportActions();
    const parsed = parseResponseText(result);

    const reportAction = parsed.actions.find((a: { type: string }) => a.type === "report");
    expect(reportAction.required_fields).toContain("report_content");

    const prAction = parsed.actions.find((a: { type: string }) => a.type === "create_pr");
    expect(prAction.required_fields).toEqual(
      expect.arrayContaining(["pr_title", "pr_body", "pr_branch"])
    );

    const noneAction = parsed.actions.find((a: { type: string }) => a.type === "none");
    expect(noneAction.required_fields).toHaveLength(0);
  });
});

describe("handleSetExportConfig", () => {
  beforeEach(() => {
    mockWriteFileSync.mockReset();
  });

  const validArgs = {
    linear_issue_id: "issue-123",
    summary: "Task completed successfully",
    action: "none",
  };

  describe("input validation", () => {
    it("rejects when linear_issue_id is missing", () => {
      const result = handleSetExportConfig({
        summary: "summary",
        action: "none",
      });
      expect(result.isError).toBe(true);
    });

    it("rejects when summary is missing", () => {
      const result = handleSetExportConfig({
        linear_issue_id: "id",
        action: "none",
      });
      expect(result.isError).toBe(true);
    });

    it("rejects when action is invalid enum value", () => {
      const result = handleSetExportConfig({
        linear_issue_id: "id",
        summary: "summary",
        action: "invalid_action",
      });
      expect(result.isError).toBe(true);
    });

    it("rejects when summary exceeds 10000 characters", () => {
      const result = handleSetExportConfig({
        linear_issue_id: "id",
        summary: "x".repeat(10001),
        action: "none",
      });
      expect(result.isError).toBe(true);
    });
  });

  describe("business rules", () => {
    it("rejects action=report without report_content", () => {
      const result = handleSetExportConfig({
        ...validArgs,
        action: "report",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("report_content");
    });

    it("rejects action=create_pr without pr config", () => {
      const result = handleSetExportConfig({
        ...validArgs,
        action: "create_pr",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("pr config");
    });

    it("accepts action=report with report_content provided", () => {
      const result = handleSetExportConfig({
        ...validArgs,
        action: "report",
        report_content: "# Analysis Report\n\nFindings...",
      });
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts action=create_pr with valid pr config", () => {
      const result = handleSetExportConfig({
        ...validArgs,
        action: "create_pr",
        pr: {
          title: "Add feature X",
          body: "This PR adds feature X",
          branch: "feature/x",
        },
      });
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts action=none without optional fields", () => {
      const result = handleSetExportConfig(validArgs);
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });

    it("accepts action=upload_workspace without optional fields", () => {
      const result = handleSetExportConfig({
        ...validArgs,
        action: "upload_workspace",
      });
      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
    });
  });

  describe("file writing", () => {
    it("writes validated config to export_config.json", () => {
      handleSetExportConfig(validArgs);

      expect(mockWriteFileSync).toHaveBeenCalledTimes(1);
      const [filePath, content, encoding] = mockWriteFileSync.mock.calls[0];
      expect(filePath).toContain("export_config.json");
      expect(encoding).toBe("utf-8");

      const written = JSON.parse(content);
      expect(written.linear_issue_id).toBe("issue-123");
      expect(written.summary).toBe("Task completed successfully");
      expect(written.action).toBe("none");
    });

    it('applies pr.base default value "main" in written config', () => {
      handleSetExportConfig({
        ...validArgs,
        action: "create_pr",
        pr: {
          title: "PR title",
          body: "PR body",
          branch: "feature/branch",
        },
      });

      const written = JSON.parse(mockWriteFileSync.mock.calls[0][1]);
      expect(written.pr.base).toBe("main");
    });

    it("returns error when writeFileSync throws", () => {
      mockWriteFileSync.mockImplementation(() => {
        throw new Error("EACCES: permission denied");
      });

      const result = handleSetExportConfig(validArgs);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("EACCES");
    });
  });

  describe("response shape", () => {
    it("returns config_path and action name in success message", () => {
      const result = handleSetExportConfig(validArgs);
      const parsed = parseResponseText(result);

      expect(parsed.success).toBe(true);
      expect(parsed.config_path).toContain("export_config.json");
      expect(parsed.message).toContain("none");
    });
  });
});
