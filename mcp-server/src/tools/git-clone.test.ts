import { describe, it, expect, vi, beforeEach } from "vitest";
import { parseResponseText, createMockContext } from "../test-utils.js";
import { gitCloneTool } from "./git-clone.js";
import type { McpToolContext } from "./types.js";

describe("gitCloneTool", () => {
  let context: McpToolContext;
  let mockExecFile: ReturnType<typeof vi.fn>;
  let mockAccess: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    context = createMockContext();
    mockExecFile = context.exec.execFile as ReturnType<typeof vi.fn>;
    mockAccess = context.fs.access as ReturnType<typeof vi.fn>;
    mockExecFile.mockResolvedValue({ stdout: "", stderr: "Cloning into 'repo'...\n" });
  });

  describe("input validation", () => {
    it("rejects when url is missing", async () => {
      const result = await gitCloneTool.handler({}, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when url is empty string", async () => {
      const result = await gitCloneTool.handler({ url: "" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await gitCloneTool.handler(null, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  describe("security validation", () => {
    it("rejects URL starting with a dash", async () => {
      const result = await gitCloneTool.handler({ url: "--upload-pack=evil" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("must not start with a dash");
    });

    it("rejects URL containing control characters", async () => {
      const result = await gitCloneTool.handler({ url: "https://example.com/repo\x00.git" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("control characters");
    });

    it("rejects directory name containing /", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git", directory: "../etc" }, context);
      expect(result.isError).toBe(true);
    });

    it("rejects directory name of '..'", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git", directory: ".." }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("must not be");
    });

    it("rejects directory name starting with a dash", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git", directory: "-malicious" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("must not start with a dash");
    });
  });

  describe("pre-execution checks", () => {
    it("returns error when target directory already exists", async () => {
      mockAccess.mockResolvedValue(undefined); // path exists

      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("already exists");
    });
  });

  describe("successful clone", () => {
    it("calls execFile with correct arguments for URL-only clone", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/my-repo.git" }, context);

      expect(mockExecFile).toHaveBeenCalledWith(
        "git",
        ["clone", "--progress", "https://github.com/org/my-repo.git", "my-repo"],
        expect.objectContaining({ cwd: "/work", timeout: 300_000 }),
      );

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.path).toBe("/work/my-repo");
    });

    it("passes --branch when branch is provided", async () => {
      await gitCloneTool.handler({ url: "https://github.com/org/repo.git", branch: "develop" }, context);

      expect(mockExecFile).toHaveBeenCalledWith(
        "git",
        ["clone", "--progress", "--branch", "develop", "https://github.com/org/repo.git", "repo"],
        expect.objectContaining({ cwd: "/work" }),
      );
    });

    it("uses custom directory name when provided", async () => {
      await gitCloneTool.handler({ url: "https://github.com/org/repo.git", directory: "custom-dir" }, context);

      expect(mockExecFile).toHaveBeenCalledWith(
        "git",
        ["clone", "--progress", "https://github.com/org/repo.git", "custom-dir"],
        expect.objectContaining({ cwd: "/work" }),
      );
    });

    it("returns success response with path, url, and branch", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git", branch: "main" }, context);

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.message).toBe("Repository cloned successfully");
      expect(parsed.path).toBe("/work/repo");
      expect(parsed.url).toBe("https://github.com/org/repo.git");
      expect(parsed.branch).toBe("main");
    });

    it("does not set isError on success", async () => {
      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git" }, context);
      expect(result.isError).toBeUndefined();
    });

    it("infers directory from URL without .git suffix", async () => {
      await gitCloneTool.handler({ url: "https://github.com/org/my-project" }, context);

      expect(mockExecFile).toHaveBeenCalledWith(
        "git",
        ["clone", "--progress", "https://github.com/org/my-project", "my-project"],
        expect.any(Object),
      );
    });

    it("infers directory from URL with trailing slashes", async () => {
      await gitCloneTool.handler({ url: "https://github.com/org/my-project///" }, context);

      expect(mockExecFile).toHaveBeenCalledWith(
        "git",
        ["clone", "--progress", "https://github.com/org/my-project///", "my-project"],
        expect.any(Object),
      );
    });
  });

  describe("error handling", () => {
    it("returns isError:true when git clone fails", async () => {
      mockExecFile.mockRejectedValue(new Error("fatal: repository 'https://bad.url/repo' not found"));

      const result = await gitCloneTool.handler({ url: "https://bad.url/repo" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toContain("not found");
    });

    it('returns "Unknown error occurred" when execFile throws non-Error', async () => {
      mockExecFile.mockRejectedValue("string error");

      const result = await gitCloneTool.handler({ url: "https://github.com/org/repo.git" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toBe("Unknown error occurred");
    });
  });
});
