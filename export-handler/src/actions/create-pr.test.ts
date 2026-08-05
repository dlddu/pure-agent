import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "../schema.js";

const { mockValidateGitHubToken, mockPrepareGitBranch, mockPushBranch, mockCreateGitHubPr } = vi.hoisted(() => ({
  mockValidateGitHubToken: vi.fn(),
  mockPrepareGitBranch: vi.fn(),
  mockPushBranch: vi.fn(),
  mockCreateGitHubPr: vi.fn().mockReturnValue("https://github.com/org/repo/pull/1"),
}));

vi.mock("../services/git.js", () => ({
  validateGitHubToken: mockValidateGitHubToken,
  prepareGitBranch: mockPrepareGitBranch,
  pushBranch: mockPushBranch,
  createGitHubPr: mockCreateGitHubPr,
}));

import { createPrHandler } from "./create-pr.js";
import { createTestActionContext } from "../test-helpers.js";

describe("createPrHandler", () => {
  const config: ExportConfig = {
    summary: "s",
    actions: ["create_pr"],
    pr: { title: "feat: new", body: "desc", branch: "feat/x", base: "main", repo: "org/repo", repo_path: "repo" },
  };

  const fullContext = createTestActionContext(config, {
    githubToken: "tok",
  });

  beforeEach(() => {
    mockValidateGitHubToken.mockReset();
    mockPrepareGitBranch.mockReset();
    mockPushBranch.mockReset();
    mockCreateGitHubPr.mockReset().mockReturnValue("https://github.com/org/repo/pull/1");
  });

  describe("validate", () => {
    it("throws when pr config is missing", () => {
      const ctx = { ...fullContext, config: { ...config, pr: undefined } } as unknown as typeof fullContext;
      expect(() => createPrHandler.validate(ctx)).toThrow("pr config is required");
    });

    it("throws when githubToken is missing", () => {
      const ctx = { ...fullContext, githubToken: undefined };
      expect(() => createPrHandler.validate(ctx)).toThrow("GITHUB_TOKEN");
    });

    it("passes with complete context", () => {
      expect(() => createPrHandler.validate(fullContext)).not.toThrow();
    });
  });

  describe("execute", () => {
    it("validates GitHub token before git operations", async () => {
      await createPrHandler.execute(fullContext);

      expect(mockValidateGitHubToken).toHaveBeenCalledWith("tok", "org/repo");
      // validate is called before prepareGitBranch
      const validateOrder = mockValidateGitHubToken.mock.invocationCallOrder[0];
      const prepareOrder = mockPrepareGitBranch.mock.invocationCallOrder[0];
      expect(validateOrder).toBeLessThan(prepareOrder);
    });

    it("stops early when token validation fails", async () => {
      mockValidateGitHubToken.mockImplementation(() => {
        throw new Error("GitHub token is invalid or expired");
      });

      await expect(createPrHandler.execute(fullContext)).rejects.toThrow("GitHub token is invalid or expired");
      expect(mockPrepareGitBranch).not.toHaveBeenCalled();
      expect(mockPushBranch).not.toHaveBeenCalled();
    });

    it("prepares git branch with correct args", async () => {
      await createPrHandler.execute(fullContext);

      expect(mockPrepareGitBranch).toHaveBeenCalledWith("/test/work/repo", "feat/x");
    });

    it("pushes branch with token", async () => {
      await createPrHandler.execute(fullContext);

      expect(mockPushBranch).toHaveBeenCalledWith("/test/work/repo", "feat/x", "tok");
    });

    it("creates GitHub PR with correct args", async () => {
      await createPrHandler.execute(fullContext);

      expect(mockCreateGitHubPr).toHaveBeenCalledWith({
        workDir: "/test/work/repo", repo: "org/repo", title: "feat: new",
        body: "desc", base: "main", branch: "feat/x", githubToken: "tok",
      });
    });

    it("returns pr_url in result", async () => {
      const result = await createPrHandler.execute(fullContext);
      expect(result).toEqual({ pr_url: "https://github.com/org/repo/pull/1" });
    });

    it("uses pr.repo from config", async () => {
      const ctx = {
        ...fullContext,
        config: { ...config, pr: { ...config.pr!, repo: "custom/repo", repo_path: "repo" } },
      };

      await createPrHandler.execute(ctx);

      expect(mockCreateGitHubPr).toHaveBeenCalledWith(
        expect.objectContaining({ repo: "custom/repo" }),
      );
    });
  });
});
