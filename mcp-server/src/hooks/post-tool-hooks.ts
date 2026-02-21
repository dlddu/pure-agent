import type { McpToolResponse, McpToolMeta, McpToolContext } from "../tools/types.js";
import { createLogger } from "../logger.js";

const log = createLogger("hooks");

export type PostToolHook = (
  response: McpToolResponse & { _meta?: McpToolMeta },
  context: McpToolContext,
) => Promise<void>;

export const sessionCommentHook: PostToolHook = async (response, context) => {
  if (!response._meta?.issueId || response.isError) return;
  const sessionId = await context.services.session.readSessionId();
  if (!sessionId) return;
  try {
    await context.services.linear.createComment(
      response._meta.issueId,
      `**Claude Code Session ID:** \`${sessionId}\``,
    );
  } catch {
    // Comment is informational — must not fail the primary operation
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
