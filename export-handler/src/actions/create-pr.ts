import { execFileSync, execSync } from "node:child_process";
import type { LinearClient } from "@linear/sdk";
import type { PrConfig } from "../schema.js";

const WORK_DIR = "/work";

export async function createPr(
  prConfig: PrConfig,
  issueId: string,
  linearClient: LinearClient
): Promise<string> {
  const { title, body, branch, base } = prConfig;
  const repo = prConfig.repo || process.env.GITHUB_REPO;

  if (!repo) {
    throw new Error("GitHub repo is required: set pr.repo or GITHUB_REPO env var");
  }

  if (!process.env.GITHUB_TOKEN) {
    throw new Error("GITHUB_TOKEN environment variable is required");
  }

  const execOpts = { cwd: WORK_DIR, stdio: "pipe" as const };
  const ghEnv = { ...process.env, GH_TOKEN: process.env.GITHUB_TOKEN };

  // Configure git for commit
  execFileSync("git", ["config", "user.name", "pure-agent"], execOpts);
  execFileSync("git", ["config", "user.email", "pure-agent@noreply"], execOpts);

  // Create branch and commit changes
  execFileSync("git", ["checkout", "-b", branch], execOpts);
  execSync("git add -A", execOpts);

  const hasChanges = execSync("git status --porcelain", execOpts).toString().trim();
  if (!hasChanges) {
    throw new Error("No changes to commit for PR");
  }

  execFileSync("git", ["commit", "-m", title], execOpts);

  // Create PR using gh CLI (execFileSync prevents shell injection)
  const prUrl = execFileSync(
    "gh",
    ["pr", "create", "--repo", repo, "--title", title, "--body", body, "--base", base, "--head", branch],
    { ...execOpts, env: ghEnv }
  )
    .toString()
    .trim();

  // Post PR link as comment on Linear issue
  const commentBody = `## GitHub Pull Request 생성됨\n\n**${title}**\n\n${prUrl}`;

  await linearClient.createComment({
    issueId,
    body: commentBody,
  });

  return prUrl;
}
