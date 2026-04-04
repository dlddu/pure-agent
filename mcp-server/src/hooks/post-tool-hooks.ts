import type { McpToolResponse, McpToolMeta, McpToolContext } from "../tools/types.js";
import { createLogger } from "../logger.js";

const log = createLogger("hooks");

export type PostToolHook = (
  response: McpToolResponse & { _meta?: McpToolMeta },
  context: McpToolContext,
) => Promise<void>;

export const sessionCommentHook: PostToolHook = async (response, context) => {
  if (!response._meta?.issueId || response.isError) return;
  const session = await context.services.session.readSessionId();
  if (!session) {
    log.warn("Session ID not found, skipping comment", { issueId: response._meta.issueId });
    return;
  }
  log.info("Posting session comment", { issueId: response._meta.issueId, source: session.source, sessionId: session.sessionId });
  try {
    await context.services.linear.createComment(
      response._meta.issueId,
      `**Claude Code Session ID (${session.source}):** \`${session.sessionId}\``,
    );
    log.info("Session comment posted", { issueId: response._meta.issueId, source: session.source });
  } catch (error) {
    log.warn("Session comment failed", { issueId: response._meta.issueId, error });
  }
};

export async function runPostToolHooks(
  hooks: PostToolHook[],
  response: McpToolResponse & { _meta?: McpToolMeta },
  context: McpToolContext,
): Promise<void> {
  for (const hook of hooks) {
    try {
      await hook(response, context);
    } catch (error) {
      log.error("Post-tool hook failed", { error });
    }
  }
}
