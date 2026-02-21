import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "../schema.js";

const { mockPostLinearComment } = vi.hoisted(() => ({
  mockPostLinearComment: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("../services/linear-comment.js", () => ({
  postLinearComment: mockPostLinearComment,
}));

import { reportHandler } from "./report.js";
import { createTestActionContext } from "../test-helpers.js";

describe("reportHandler", () => {
  const baseConfig: ExportConfig = {
    linear_issue_id: "TEAM-1",
    summary: "s",
    actions: ["report"],
    report_content: "Analysis result",
  };

  const baseContext = createTestActionContext(baseConfig);

  beforeEach(() => {
    mockPostLinearComment.mockReset().mockResolvedValue(undefined);
  });

  it("validate throws when issueId is 'none'", () => {
    const noneConfig: ExportConfig = { ...baseConfig, linear_issue_id: "none" };
    const ctx = createTestActionContext(noneConfig);
    expect(() => reportHandler.validate(ctx)).toThrow("linear_issue_id must be set");
  });

  it("validate throws when report_content is missing", () => {
    const ctx = { ...baseContext, config: { ...baseConfig, report_content: undefined } } as unknown as typeof baseContext;
    expect(() => reportHandler.validate(ctx)).toThrow("report_content is required");
  });

  it("validate passes when report_content is present", () => {
    expect(() => reportHandler.validate(baseContext)).not.toThrow();
  });

  it("execute returns empty result", async () => {
    const result = await reportHandler.execute(baseContext);
    expect(result).toEqual({});
  });

  it("execute posts report comment to Linear", async () => {
    await reportHandler.execute(baseContext);

    expect(mockPostLinearComment).toHaveBeenCalledWith(
      baseContext.linearClient,
      "TEAM-1",
      expect.stringContaining("Analysis result"),
      "report",
    );
  });

  it("execute includes report header in comment body", async () => {
    await reportHandler.execute(baseContext);

    expect(mockPostLinearComment).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      expect.stringContaining("## 분석 리포트"),
      expect.anything(),
    );
  });
});
