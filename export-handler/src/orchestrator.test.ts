import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "./schema.js";
import type { ActionContext } from "./actions/types.js";

// Mock action registry — each action uses shared mockValidate/mockExecute
const { mockValidate, mockExecute } = vi.hoisted(() => ({
  mockValidate: vi.fn(),
  mockExecute: vi.fn().mockResolvedValue({}),
}));

vi.mock("./actions/registry.js", () => ({
  actionRegistry: {
    none: { validate: mockValidate, execute: mockExecute },
    create_pr: { validate: mockValidate, execute: mockExecute },
  },
}));

import { processExport } from "./orchestrator.js";
import { createTestActionDeps } from "./test-helpers.js";

describe("processExport", () => {
  beforeEach(() => {
    mockValidate.mockReset();
    mockExecute.mockReset().mockResolvedValue({});
  });

  const validConfig: ExportConfig = {
    summary: "작업 완료",
    actions: ["none"],
  };

  it("에러 없이 정상 완료되며 빈 결과를 반환한다", async () => {
    await expect(processExport(validConfig, createTestActionDeps())).resolves.toEqual({});
  });

  it("handler.validate → handler.execute 순서로 호출한다", async () => {
    const callOrder: string[] = [];
    mockValidate.mockImplementation(() => callOrder.push("validate"));
    mockExecute.mockImplementation(async () => { callOrder.push("execute"); return {}; });

    await processExport(validConfig, createTestActionDeps());

    expect(callOrder).toEqual(["validate", "execute"]);
  });

  it("올바른 ActionContext를 handler에 전달한다", async () => {
    const deps = createTestActionDeps();

    await processExport(validConfig, deps);

    const expectedContext: ActionContext = {
      config: validConfig,
      ...deps,
    };
    expect(mockValidate).toHaveBeenCalledWith(expectedContext);
    expect(mockExecute).toHaveBeenCalledWith(expectedContext);
  });

  it('actions=["create_pr"]이면 handler.execute를 호출한다', async () => {
    const config: ExportConfig = {
      ...validConfig,
      actions: ["create_pr"],
      pr: { title: "feat: 새 기능", body: "새 기능 추가", branch: "feature/new", base: "main", repo: "org/repo", repo_path: "repo" },
    };
    const deps = createTestActionDeps({ githubToken: "test-token" });

    await processExport(config, deps);

    expect(mockExecute).toHaveBeenCalledOnce();
  });

  it("handler.validate 에러를 전파한다", async () => {
    mockValidate.mockImplementation(() => {
      throw new Error("validation failed");
    });

    await expect(processExport(validConfig, createTestActionDeps())).rejects.toThrow(
      "validation failed",
    );
    expect(mockExecute).not.toHaveBeenCalled();
  });

  it("handler.execute 에러를 전파한다", async () => {
    mockExecute.mockRejectedValue(new Error("execute failed"));

    await expect(processExport(validConfig, createTestActionDeps())).rejects.toThrow(
      "execute failed",
    );
  });

  it("액션 결과를 병합하여 반환한다", async () => {
    const config: ExportConfig = {
      ...validConfig,
      actions: ["create_pr"],
      pr: { title: "t", body: "b", branch: "br", base: "main", repo: "o/r", repo_path: "r" },
    };
    const deps = createTestActionDeps({ githubToken: "tok" });

    mockExecute.mockResolvedValueOnce({ pr_url: "https://github.com/org/repo/pull/1" });

    const result = await processExport(config, deps);

    expect(result).toEqual({
      pr_url: "https://github.com/org/repo/pull/1",
    });
  });
});
