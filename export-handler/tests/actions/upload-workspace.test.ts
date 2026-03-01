import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "../../src/schema.js";

const { mockCreateWorkspaceZip, mockUploadToLinear } = vi.hoisted(() => ({
  mockCreateWorkspaceZip: vi.fn().mockReturnValue({ zipBuffer: Buffer.from("z"), zipSizeBytes: 100 }),
  mockUploadToLinear: vi.fn().mockResolvedValue("https://asset.example.com/file.zip"),
}));

vi.mock("../../src/services/workspace-zip.js", () => ({
  createWorkspaceZip: mockCreateWorkspaceZip,
  uploadToLinear: mockUploadToLinear,
}));

const { mockPostLinearComment } = vi.hoisted(() => ({
  mockPostLinearComment: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("../../src/services/linear-comment.js", () => ({
  postLinearComment: mockPostLinearComment,
}));

import { uploadWorkspaceHandler } from "../../src/actions/upload-workspace.js";
import { createTestActionContext } from "../test-helpers.js";

describe("uploadWorkspaceHandler", () => {
  const config: ExportConfig = {
    linear_issue_id: "TEAM-1",
    summary: "s",
    actions: ["upload_workspace"],
  };
  const context = createTestActionContext(config);

  beforeEach(() => {
    mockCreateWorkspaceZip.mockReset().mockReturnValue({ zipBuffer: Buffer.from("z"), zipSizeBytes: 100 });
    mockUploadToLinear.mockReset().mockResolvedValue("https://asset.example.com/file.zip");
    mockPostLinearComment.mockReset().mockResolvedValue(undefined);
  });

  it("validate does not throw with valid issueId", () => {
    expect(() => uploadWorkspaceHandler.validate(context)).not.toThrow();
  });

  it("validate throws when issueId is 'none'", () => {
    const noneConfig: ExportConfig = { ...config, linear_issue_id: "none" };
    const ctx = createTestActionContext(noneConfig);
    expect(() => uploadWorkspaceHandler.validate(ctx)).toThrow("linear_issue_id must be set");
  });

  it("execute creates workspace zip with correct args", async () => {
    await uploadWorkspaceHandler.execute(context);

    expect(mockCreateWorkspaceZip).toHaveBeenCalledWith("/test/work", "/test/tmp/workspace.zip");
  });

  it("execute uploads zip to Linear", async () => {
    await uploadWorkspaceHandler.execute(context);

    expect(mockUploadToLinear).toHaveBeenCalledWith({
      linearClient: context.linearClient,
      zipBuffer: Buffer.from("z"),
      zipSizeBytes: 100,
      filename: expect.stringContaining("workspace-"),
    });
  });

  it("execute returns asset_url in result", async () => {
    const result = await uploadWorkspaceHandler.execute(context);
    expect(result).toEqual({ asset_url: "https://asset.example.com/file.zip" });
  });

  it("execute posts comment with asset URL", async () => {
    await uploadWorkspaceHandler.execute(context);

    expect(mockPostLinearComment).toHaveBeenCalledWith(
      context.linearClient,
      "TEAM-1",
      expect.stringContaining("https://asset.example.com/file.zip"),
      "upload",
    );
  });
});
