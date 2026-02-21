import { execFileSync as _execFileSync } from "node:child_process";
import { existsSync as _existsSync } from "node:fs";
import { wrapError } from "../errors.js";

export interface GitDeps {
  execFileSync: typeof _execFileSync;
  existsSync: typeof _existsSync;
}

const defaultGitDeps: GitDeps = { execFileSync: _execFileSync, existsSync: _existsSync };

/** Build exec env with GH_TOKEN for gh CLI and git credential helpers. */
function ghTokenEnv(githubToken: string): NodeJS.ProcessEnv {
  return { ...process.env, GH_TOKEN: githubToken };
}

/**
 * Validate that the GitHub token is valid and has push access to the target repo.
 * Call this before git operations to surface auth issues with clear messages.
 */
export function validateGitHubToken(
  token: string, repo: string,
  deps: GitDeps = defaultGitDeps,
): void {
  if (!token.trim()) {
    throw new Error("GITHUB_TOKEN is empty or whitespace");
  }

  const env = ghTokenEnv(token);

  try {
    deps.execFileSync("gh", ["auth", "status"], { stdio: "pipe", env });
  } catch (error) {
    throw wrapError(error, "GitHub token is invalid or expired");
  }

  try {
    const output = deps
      .execFileSync("gh", ["api", `repos/${repo}`, "--jq", ".permissions.push"], { stdio: "pipe", env })
      .toString()
      .trim();

    if (output !== "true") {
      throw new Error(`GitHub token does not have push permission to ${repo}`);
    }
  } catch (error) {
    if (error instanceof Error && error.message.includes("push permission")) {
      throw error;
    }
    throw wrapError(error, `Cannot access repository ${repo}`);
  }
}

/**
 * Checkout an existing branch that the agent has already prepared with commits.
 * Does NOT reset the branch or create new commits – the agent handles that.
 */
export function prepareGitBranch(
  workDir: string, branch: string,
  deps: GitDeps = defaultGitDeps,
): void {
  if (!deps.existsSync(workDir)) {
    throw new Error(`Repository directory does not exist: ${workDir}`);
  }

  const execOpts = { cwd: workDir, stdio: "pipe" as const };

  try {
    // Container environments often have different uid for repo owner vs current user.
    // Mark workDir as safe to prevent Git's "dubious ownership" error.
    deps.execFileSync("git", ["config", "--global", "--add", "safe.directory", workDir], { stdio: "pipe" as const });
    deps.execFileSync("git", ["checkout", branch], execOpts);
  } catch (error) {
    throw wrapError(error, "Git operation failed");
  }
}

export function pushBranch(
  workDir: string, branch: string, githubToken: string,
  deps: GitDeps = defaultGitDeps,
): void {
  const env = ghTokenEnv(githubToken);
  try {
    // Configure gh CLI as git credential helper so git push can authenticate.
    // gh reads GH_TOKEN from the environment automatically.
    deps.execFileSync("gh", ["auth", "setup-git"], { stdio: "pipe", env });
    deps.execFileSync("git", ["push", "-u", "origin", branch], {
      cwd: workDir,
      stdio: "pipe",
      env,
    });
  } catch (error) {
    throw wrapError(error, "Git push failed");
  }
}

export interface CreatePrOptions {
  workDir: string;
  repo: string;
  title: string;
  body: string;
  base: string;
  branch: string;
  githubToken: string;
}

export function createGitHubPr(opts: CreatePrOptions, deps: GitDeps = defaultGitDeps): string {
  const { workDir, repo, title, body, base, branch, githubToken } = opts;
  try {
    return deps.execFileSync(
      "gh",
      ["pr", "create", "--repo", repo, "--title", title, "--body", body, "--base", base, "--head", branch],
      { cwd: workDir, stdio: "pipe", env: ghTokenEnv(githubToken) },
    )
      .toString()
      .trim();
  } catch (error) {
    throw wrapError(error, "GitHub CLI 'gh pr create' failed");
  }
}
