import type { LinearClient } from "@linear/sdk";
import { wrapError } from "../errors.js";
import { createLogger } from "../logger.js";

const log = createLogger("linear-comment");

/** Allowed error-context values, one per call site. */
export type CommentContext = "summary" | "report" | "upload" | "PR link";

export async function postLinearComment(
  client: LinearClient,
  issueId: string,
  body: string,
  errorContext: CommentContext,
): Promise<void> {
  log.info(`Posting ${errorContext} comment to issue ${issueId}`);
  try {
    const result = await client.createComment({ issueId, body });
    if (!result.success) {
      throw new Error("Linear API returned success=false");
    }
  } catch (error) {
    throw wrapError(error, `Failed to create ${errorContext} comment on Linear issue`);
  }
}
