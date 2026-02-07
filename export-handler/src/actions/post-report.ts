import type { LinearClient } from "@linear/sdk";

export async function postReport(
  client: LinearClient,
  issueId: string,
  reportContent: string
): Promise<void> {
  const body = `## 분석 리포트\n\n${reportContent}`;

  const result = await client.createComment({
    issueId,
    body,
  });

  if (!result.success) {
    throw new Error("Failed to create report comment on Linear issue");
  }
}
