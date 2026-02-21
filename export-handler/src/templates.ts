// Korean markdown templates for Linear comments.
// Centralized here so all comment formatting is in one place.

export function summaryComment(summary: string): string {
  return `## Agent 작업 요약\n\n${summary}`;
}

export function reportComment(reportContent: string): string {
  return `## 분석 리포트\n\n${reportContent}`;
}

export function workspaceUploadComment(filename: string, assetUrl: string): string {
  return `## Workspace 압축 파일\n\n작업 workspace 전체가 첨부되었습니다.\n\n[${filename}](${assetUrl})`;
}

export function prCreatedComment(title: string, prUrl: string): string {
  return `## GitHub Pull Request 생성됨\n\n**${title}**\n\n${prUrl}`;
}
