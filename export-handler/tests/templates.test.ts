import { describe, it, expect } from "vitest";
import {
  summaryComment,
  reportComment,
  workspaceUploadComment,
  prCreatedComment,
} from "../src/templates.js";

describe("templates", () => {
  it("summaryComment includes header and content", () => {
    const result = summaryComment("작업 완료");
    expect(result).toBe("## Agent 작업 요약\n\n작업 완료");
  });

  it("reportComment includes header and content", () => {
    const result = reportComment("결과 내용");
    expect(result).toBe("## 분석 리포트\n\n결과 내용");
  });

  it("workspaceUploadComment includes filename and URL", () => {
    const result = workspaceUploadComment("ws.zip", "https://example.com/ws.zip");
    expect(result).toContain("## Workspace 압축 파일");
    expect(result).toContain("[ws.zip](https://example.com/ws.zip)");
  });

  it("prCreatedComment includes title and URL", () => {
    const result = prCreatedComment("feat: X", "https://github.com/org/repo/pull/1");
    expect(result).toContain("## GitHub Pull Request 생성됨");
    expect(result).toContain("**feat: X**");
    expect(result).toContain("https://github.com/org/repo/pull/1");
  });
});
