import { describe, it, expect, vi, beforeEach } from "vitest";
import type { GitDeps } from "../../src/services/git.js";
import { validateGitHubToken, prepareGitBranch, pushBranch, createGitHubPr } from "../../src/services/git.js";

function createMockGitDeps(): GitDeps {
  return {
    execFileSync: vi.fn().mockReturnValue(Buffer.from("")),
    existsSync: vi.fn().mockReturnValue(true),
  };
}

describe("prepareGitBranch", () => {
  let deps: GitDeps;

  beforeEach(() => {
    deps = createMockGitDeps();
  });

  it("safe.directory 설정 후 기존 브랜치로 checkout한다", () => {
    prepareGitBranch("/work", "feature/test", deps);

    const calls = (deps.execFileSync as ReturnType<typeof vi.fn>).mock.calls;
    expect(calls).toHaveLength(2);
    expect(calls[0]).toEqual(["git", ["config", "--global", "--add", "safe.directory", "/work"], expect.any(Object)]);
    expect(calls[1]).toEqual(["git", ["checkout", "feature/test"], expect.any(Object)]);
  });

  it("작업 디렉토리가 없으면 명확한 에러를 던진다", () => {
    (deps.existsSync as ReturnType<typeof vi.fn>).mockReturnValue(false);

    expect(() => prepareGitBranch("/work/nonexistent", "feature/test", deps)).toThrow(
      "Repository directory does not exist: /work/nonexistent",
    );
    expect(deps.execFileSync).not.toHaveBeenCalled();
  });

  it("git 명령어 실패 시 컨텍스트 포함 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>).mockImplementation(() => {
      throw new Error("git not found");
    });

    expect(() => prepareGitBranch("/work", "feature/test", deps)).toThrow(
      "Git operation failed: git not found",
    );
  });
});

describe("pushBranch", () => {
  let deps: GitDeps;

  beforeEach(() => {
    deps = createMockGitDeps();
  });

  it("gh auth setup-git으로 credential helper를 설정한 후 push한다", () => {
    pushBranch("/work", "feature/test", "my-token", deps);

    const calls = (deps.execFileSync as ReturnType<typeof vi.fn>).mock.calls;
    expect(calls).toHaveLength(2);
    expect(calls[0]).toEqual([
      "gh", ["auth", "setup-git"],
      expect.objectContaining({ env: expect.objectContaining({ GH_TOKEN: "my-token" }) }),
    ]);
    expect(calls[1]).toEqual([
      "git", ["push", "-u", "origin", "feature/test"],
      expect.objectContaining({
        cwd: "/work",
        env: expect.objectContaining({ GH_TOKEN: "my-token" }),
      }),
    ]);
  });

  it("push 실패 시 컨텍스트 포함 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>)
      .mockReturnValueOnce(Buffer.from(""))   // gh auth setup-git succeeds
      .mockImplementationOnce(() => { throw new Error("remote rejected"); });

    expect(() => pushBranch("/work", "feature/test", "my-token", deps)).toThrow(
      "Git push failed: remote rejected",
    );
  });
});

describe("validateGitHubToken", () => {
  let deps: GitDeps;

  beforeEach(() => {
    deps = createMockGitDeps();
  });

  it("빈 토큰이면 즉시 에러를 던진다", () => {
    expect(() => validateGitHubToken("", "org/repo", deps)).toThrow(
      "GITHUB_TOKEN is empty or whitespace",
    );
    expect(() => validateGitHubToken("   ", "org/repo", deps)).toThrow(
      "GITHUB_TOKEN is empty or whitespace",
    );
    expect(deps.execFileSync).not.toHaveBeenCalled();
  });

  it("gh auth status 실패 시 토큰 무효 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>).mockImplementation(() => {
      throw new Error("not logged in");
    });

    expect(() => validateGitHubToken("bad-token", "org/repo", deps)).toThrow(
      "GitHub token is invalid or expired: not logged in",
    );
  });

  it("레포 접근 불가 시 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>)
      .mockReturnValueOnce(Buffer.from(""))   // gh auth status succeeds
      .mockImplementationOnce(() => { throw new Error("Not Found"); });

    expect(() => validateGitHubToken("my-token", "org/repo", deps)).toThrow(
      "Cannot access repository org/repo: Not Found",
    );
  });

  it("push 권한이 없으면 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>)
      .mockReturnValueOnce(Buffer.from(""))          // gh auth status
      .mockReturnValueOnce(Buffer.from("false\n"));  // permissions.push

    expect(() => validateGitHubToken("my-token", "org/repo", deps)).toThrow(
      "GitHub token does not have push permission to org/repo",
    );
  });

  it("토큰이 유효하고 push 권한이 있으면 정상 통과한다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>)
      .mockReturnValueOnce(Buffer.from(""))         // gh auth status
      .mockReturnValueOnce(Buffer.from("true\n"));  // permissions.push

    expect(() => validateGitHubToken("good-token", "org/repo", deps)).not.toThrow();

    const calls = (deps.execFileSync as ReturnType<typeof vi.fn>).mock.calls;
    expect(calls[0]).toEqual([
      "gh", ["auth", "status"],
      expect.objectContaining({ env: expect.objectContaining({ GH_TOKEN: "good-token" }) }),
    ]);
    expect(calls[1]).toEqual([
      "gh", ["api", "repos/org/repo", "--jq", ".permissions.push"],
      expect.objectContaining({ env: expect.objectContaining({ GH_TOKEN: "good-token" }) }),
    ]);
  });
});

describe("createGitHubPr", () => {
  let deps: GitDeps;

  beforeEach(() => {
    deps = createMockGitDeps();
  });

  it("gh pr create를 올바른 인자로 실행하고 URL을 반환한다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>).mockReturnValue(Buffer.from("  https://github.com/org/repo/pull/1\n"));

    const url = createGitHubPr({
      workDir: "/work", repo: "org/repo", title: "feat: title",
      body: "body text", base: "main", branch: "feature/test", githubToken: "my-token",
    }, deps);

    expect(url).toBe("https://github.com/org/repo/pull/1");
    expect(deps.execFileSync).toHaveBeenCalledWith(
      "gh",
      ["pr", "create", "--repo", "org/repo", "--title", "feat: title", "--body", "body text", "--base", "main", "--head", "feature/test"],
      expect.objectContaining({
        cwd: "/work",
        env: expect.objectContaining({ GH_TOKEN: "my-token" }),
      }),
    );
  });

  it("gh 실패 시 컨텍스트 포함 에러를 던진다", () => {
    (deps.execFileSync as ReturnType<typeof vi.fn>).mockImplementation(() => {
      throw new Error("gh: command not found");
    });

    expect(() => createGitHubPr({
      workDir: "/work", repo: "org/repo", title: "title",
      body: "body", base: "main", branch: "branch", githubToken: "token",
    }, deps)).toThrow(
      "GitHub CLI 'gh pr create' failed: gh: command not found",
    );
  });
});
