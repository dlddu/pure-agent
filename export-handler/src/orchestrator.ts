import type { LinearClient } from "@linear/sdk";
import type { ExportConfig } from "./schema.js";
import { postLinearComment } from "./services/linear-comment.js";
import { actionRegistry } from "./actions/registry.js";
import type { ActionContext, ActionDeps, ActionResult } from "./actions/types.js";
import { summaryComment } from "./templates.js";
import { wrapError } from "./errors.js";
import { createLogger } from "./logger.js";

const log = createLogger("orchestrator");

export async function processExport(
  exportConfig: ExportConfig,
  linearClient: LinearClient,
  deps: ActionDeps,
): Promise<ActionResult> {
  const hasLinearIssue = exportConfig.linear_issue_id != null && exportConfig.linear_issue_id !== "none";

  // Step 1: Post summary only when Linear issue exists
  if (hasLinearIssue) {
    log.info("Posting summary comment to Linear...");
    await postLinearComment(linearClient, exportConfig.linear_issue_id!, summaryComment(exportConfig.summary), "summary");
    log.info("Summary posted");
  } else {
    log.info("No valid linear_issue_id. Skipping Linear summary comment.");
  }

  // Step 2: Validate and execute each action sequentially
  const context: ActionContext = {
    linearClient,
    issueId: exportConfig.linear_issue_id,
    config: exportConfig,
    ...deps,
  };

  const results: ActionResult = {};

  for (const action of exportConfig.actions) {
    const handler = actionRegistry[action];
    log.info(`Executing action: ${action}`);
    try {
      handler.validate(context);
    } catch (error) {
      throw wrapError(error, `Validation failed for action '${action}'`);
    }
    const result = await handler.execute(context);
    Object.assign(results, result);
    log.info(`Action '${action}' completed`);
  }

  return results;
}
