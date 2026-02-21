import type { ActionHandler, ActionContext, ActionResult } from "./types.js";
import { postLinearComment } from "../services/linear-comment.js";
import { reportComment } from "../templates.js";
import { createLogger } from "../logger.js";

const log = createLogger("action:report");

export const reportHandler: ActionHandler = {
  validate({ config, issueId }: ActionContext): void {
    if (!issueId || issueId === "none") {
      throw new Error("report action requires a valid Linear issue (linear_issue_id must be set)");
    }
    if (!config.report_content) {
      throw new Error("report_content is required for action 'report'");
    }
  },
  async execute(context: ActionContext): Promise<ActionResult> {
    const report_content = context.config.report_content!;
    log.info("Action: report. Posting analysis report...");
    await postLinearComment(context.linearClient, context.issueId!, reportComment(report_content), "report");
    log.info("Report posted");
    return {};
  },
};
