import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "../src/schema.js";
import type { ActionContext } from "../src/actions/types.js";

// Mock linear-comment service
const { mockPostLinearComment } = vi.hoisted(() => ({
  mockPostLinearComment: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("../src/services/linear-comment.js", () => ({
  postLinearComment: mockPostLinearComment,
}));

// Mock action registry — each action uses shared mockValidate/mockExecute
const { mockValidate, mockExecute } = vi.hoisted(() => ({
  mockValidate: vi.fn(),
  mockExecute: vi.fn().mockResolvedValue({}),
}));

vi.mock("../src/actions/registry.js", () => ({
  actionRegistry: {
    none: { validate: mockValidate, execute: mockExecute },
    upload_workspace: { validate: mockValidate, execute: mockExecute },
    report: { validate: mockValidate, execute: mockExecute },
    create_pr: { validate: mockValidate, execute: mockExecute },
    continue: { validate: mockValidate, execute: mockExecute },
  },
}));

import { processExport } from "../src/orchestrator.js";
import { createTestActionDeps, createMockLinearClient } from "./test-helpers.js";

describe("processExport", () => {
  beforeEach(() => {
    mockPostLinearComment.mockReset().mockResolvedValue(undefined);
    mockValidate.mockReset();
    mockExecute.mockReset().mockResolvedValue({});
  });

  describe('linear_issue_id가 "none"인 경우', () => {
    const noneConfig: ExportConfig = {
      linear_issue_id: "none",
      summary: "이슈 없이 작업 완료",
      actions: ["none"],
    };

    it("Linear summary 코멘트를 스킵하되 액션은 실행한다", async () => {
      const client = createMockLinearClient();

      await processExport(noneConfig, client, createTestActionDeps());

      expect(mockPostLinearComment).not.toHaveBeenCalled();
      expect(mockValidate).toHaveBeenCalledOnce();
      expect(mockExecute).toHaveBeenCalledOnce();
    });

    it("에러 없이 정상 완료되며 빈 결과를 반환한다", async () => {
      const client = createMockLinearClient();

      await expect(processExport(noneConfig, client, createTestActionDeps())).resolves.toEqual({});
    });

    it("summary 값과 관계없이 Linear summary 코멘트를 스킵한다", async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        linear_issue_id: "none",
        summary: "매우 긴 요약 내용이 포함되어도 Linear API는 호출되지 않아야 합니다.",
        actions: ["none"],
      };

      await processExport(config, client, createTestActionDeps());

      expect(mockPostLinearComment).not.toHaveBeenCalled();
    });
  });

  describe("linear_issue_id가 없는 경우", () => {
    const noIssueConfig: ExportConfig = {
      summary: "이슈 없이 작업 완료",
      actions: ["none"],
    };

    it("Linear summary 코멘트를 스킵하되 액션은 실행한다", async () => {
      const client = createMockLinearClient();

      await processExport(noIssueConfig, client, createTestActionDeps());

      expect(mockPostLinearComment).not.toHaveBeenCalled();
      expect(mockValidate).toHaveBeenCalledOnce();
      expect(mockExecute).toHaveBeenCalledOnce();
    });

    it("issueId가 undefined인 ActionContext를 전달한다", async () => {
      const client = createMockLinearClient();
      const deps = createTestActionDeps();

      await processExport(noIssueConfig, client, deps);

      const expectedContext: ActionContext = {
        linearClient: client,
        issueId: undefined,
        config: noIssueConfig,
        ...deps,
      };
      expect(mockValidate).toHaveBeenCalledWith(expectedContext);
    });
  });

  describe("유효한 linear_issue_id인 경우", () => {
    const validConfig: ExportConfig = {
      linear_issue_id: "TEAM-123",
      summary: "작업 완료",
      actions: ["none"],
    };

    it("summary를 먼저 포스트한다", async () => {
      const client = createMockLinearClient();

      await processExport(validConfig, client, createTestActionDeps());

      expect(mockPostLinearComment).toHaveBeenCalledWith(
        client, "TEAM-123", expect.stringContaining("작업 완료"), "summary",
      );
    });

    it("handler.validate → handler.execute 순서로 호출한다", async () => {
      const callOrder: string[] = [];
      mockValidate.mockImplementation(() => callOrder.push("validate"));
      mockExecute.mockImplementation(async () => { callOrder.push("execute"); return {}; });

      const client = createMockLinearClient();
      await processExport(validConfig, client, createTestActionDeps());

      expect(callOrder).toEqual(["validate", "execute"]);
    });

    it("올바른 ActionContext를 handler에 전달한다", async () => {
      const client = createMockLinearClient();
      const deps = createTestActionDeps();

      await processExport(validConfig, client, deps);

      const expectedContext: ActionContext = {
        linearClient: client,
        issueId: "TEAM-123",
        config: validConfig,
        ...deps,
      };
      expect(mockValidate).toHaveBeenCalledWith(expectedContext);
      expect(mockExecute).toHaveBeenCalledWith(expectedContext);
    });

    it('actions=["upload_workspace"]이면 handler.execute를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = { ...validConfig, actions: ["upload_workspace"] };

      await processExport(config, client, createTestActionDeps());

      expect(mockPostLinearComment).toHaveBeenCalledOnce();
      expect(mockExecute).toHaveBeenCalledOnce();
    });

    it('actions=["report"]이면 handler.execute를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        actions: ["report"],
        report_content: "# 분석 결과\n\n문제 없음",
      };

      await processExport(config, client, createTestActionDeps());

      expect(mockPostLinearComment).toHaveBeenCalledOnce();
      expect(mockExecute).toHaveBeenCalledOnce();
    });

    it('actions=["create_pr"]이면 handler.execute를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        actions: ["create_pr"],
        pr: { title: "feat: 새 기능", body: "새 기능 추가", branch: "feature/new", base: "main", repo: "org/repo", repo_path: "repo" },
      };
      const deps = createTestActionDeps({ githubToken: "test-token" });

      await processExport(config, client, deps);

      expect(mockPostLinearComment).toHaveBeenCalledOnce();
      expect(mockExecute).toHaveBeenCalledOnce();
    });

    it("다중 액션을 순차적으로 실행한다", async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        actions: ["upload_workspace", "report"],
        report_content: "content",
      };

      await processExport(config, client, createTestActionDeps());

      expect(mockValidate).toHaveBeenCalledTimes(2);
      expect(mockExecute).toHaveBeenCalledTimes(2);
    });

    it("handler.validate 에러를 전파한다", async () => {
      mockValidate.mockImplementation(() => {
        throw new Error("validation failed");
      });
      const client = createMockLinearClient();

      await expect(processExport(validConfig, client, createTestActionDeps())).rejects.toThrow(
        "validation failed",
      );
      expect(mockExecute).not.toHaveBeenCalled();
    });

    it("handler.execute 에러를 전파한다", async () => {
      mockExecute.mockRejectedValue(new Error("execute failed"));
      const client = createMockLinearClient();

      await expect(processExport(validConfig, client, createTestActionDeps())).rejects.toThrow(
        "execute failed",
      );
    });

    it("다중 액션의 결과를 병합하여 반환한다", async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        actions: ["upload_workspace", "create_pr"],
        pr: { title: "t", body: "b", branch: "br", base: "main", repo: "o/r", repo_path: "r" },
      };
      const deps = createTestActionDeps({ githubToken: "tok" });

      mockExecute
        .mockResolvedValueOnce({ asset_url: "https://example.com/file.zip" })
        .mockResolvedValueOnce({ pr_url: "https://github.com/org/repo/pull/1" });

      const result = await processExport(config, client, deps);

      expect(result).toEqual({
        asset_url: "https://example.com/file.zip",
        pr_url: "https://github.com/org/repo/pull/1",
      });
    });
  });
});
