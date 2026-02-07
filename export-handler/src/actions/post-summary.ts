import type { LinearClient } from "@linear/sdk";

export async function postSummary(
  client: LinearClient,
  issueId: string,
  summary: string
): Promise<void> {
  const body = `## Agent 작업 요약\n\n${summary}`;

  const result = await client.createComment({
    issueId,
    body,
  });

  if (!result.success) {
    throw new Error("Failed to create summary comment on Linear issue");
  }
}
