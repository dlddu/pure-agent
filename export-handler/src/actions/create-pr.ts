import { resolve } from "node:path";
import type { ActionHandler, ActionContext, ActionResult } from "./types.js";
import { validateGitHubToken, prepareGitBranch, pushBranch, createGitHubPr } from "../services/git.js";
import { postLinearComment } from "../services/linear-comment.js";
import { prCreatedComment } from "../templates.js";
import { createLogger } from "../logger.js";

const log = createLogger("action:create-pr");

export const createPrHandler: ActionHandler = {
  validate({ config, githubToken }: ActionContext): void {
    if (!config.pr) {
      throw new Error("pr config is required for action 'create_pr'");
    }
    if (!githubToken) {
      throw new Error("GITHUB_TOKEN environment variable is required for create_pr action");
    }
  },
  async execute(context: ActionContext): Promise<ActionResult> {
    const { config, issueId, linearClient, workDir, githubToken } = context;
    // pr (including pr.repo) is guaranteed by schema and validate()
    const { title, body, branch, base, repo, repo_path } = config.pr!;
    const token = githubToken!;
    const repoDir = resolve(workDir, repo_path);

    log.info("Action: create_pr. Creating GitHub PR...");

    validateGitHubToken(token, repo);
    prepareGitBranch(repoDir, branch);
    pushBranch(repoDir, branch, token);
    const prUrl = createGitHubPr({ workDir: repoDir, repo, title, body, base, branch, githubToken: token });

    if (issueId && issueId !== "none") {
      await postLinearComment(linearClient, issueId, prCreatedComment(title, prUrl), "PR link");
    } else {
      log.info("No Linear issue. Skipping PR comment.");
    }

    log.info(`PR created: ${prUrl}`);

    return { pr_url: prUrl };
  },
};
