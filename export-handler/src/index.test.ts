import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock node:fs
const { mockExistsSync, mockReadFileSync } = vi.hoisted(() => ({
  mockExistsSync: vi.fn(),
  mockReadFileSync: vi.fn(),
}));

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return { ...actual, existsSync: mockExistsSync, readFileSync: mockReadFileSync };
});

// Mock config
const { mockParseConfig, mockDerivePaths } = vi.hoisted(() => ({
  mockParseConfig: vi.fn(),
  mockDerivePaths: vi.fn(),
}));

vi.mock("./config.js", () => ({
  parseConfig: mockParseConfig,
  derivePaths: mockDerivePaths,
  deriveFallbackArgoPaths: vi.fn().mockReturnValue({
    exportConfigPath: "/work/export_config.json",
    argoOutputPath: "/tmp/export_config.json",
  }),
}));

// Mock services
const { mockEnsureArgoOutput, mockWriteActionResults } = vi.hoisted(() => ({
  mockEnsureArgoOutput: vi.fn(),
  mockWriteActionResults: vi.fn(),
}));

vi.mock("./services/argo-output.js", () => ({
  ensureArgoOutput: mockEnsureArgoOutput,
  writeActionResults: mockWriteActionResults,
}));

const { mockProcessExport } = vi.hoisted(() => ({
  mockProcessExport: vi.fn().mockResolvedValue({}),
}));

vi.mock("./orchestrator.js", () => ({
  processExport: mockProcessExport,
}));

// Mock LinearClient
const mockLinearClientInstances: { opts: unknown }[] = [];
vi.mock("@linear/sdk", () => ({
  LinearClient: class MockLinearClient {
    constructor(public opts: unknown) {
      mockLinearClientInstances.push(this);
    }
  },
}));

import { run } from "./index.js";
import { createTestAppConfig } from "./test-helpers.js";

const defaultPaths = {
  exportConfigPath: "/test/work/export_config.json",
  argoOutputPath: "/test/tmp/export_config.json",
  actionResultsOutputPath: "/test/tmp/action_results.json",
  zipOutputPath: "/test/tmp/workspace.zip",
};

const defaultConfig = createTestAppConfig();

describe("run (index.ts entry point)", () => {
  beforeEach(() => {
    mockParseConfig.mockReset().mockReturnValue(defaultConfig);
    mockDerivePaths.mockReset().mockReturnValue(defaultPaths);
    mockEnsureArgoOutput.mockReset();
    mockWriteActionResults.mockReset();
    mockExistsSync.mockReset().mockReturnValue(false);
    mockReadFileSync.mockReset();
    mockProcessExport.mockReset().mockResolvedValue({});
    mockLinearClientInstances.length = 0;
  });

  it("export_config.json이 없으면 export action을 스킵한다", async () => {
    mockExistsSync.mockReturnValue(false);

    await run();

    expect(mockEnsureArgoOutput).not.toHaveBeenCalled();
    expect(mockProcessExport).not.toHaveBeenCalled();
  });

  it("정상 경로: config 파싱 → processExport 호출", async () => {
    const exportConfig = {
      linear_issue_id: "TEAM-1",
      summary: "done",
      actions: ["none"],
    };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));

    await run();

    expect(mockProcessExport).toHaveBeenCalledWith(
      exportConfig,
      expect.anything(),
      {
        workDir: defaultConfig.workDir,
        zipOutputPath: defaultPaths.zipOutputPath,
        githubToken: undefined,
      },
    );
  });

  it("LinearClient 생성 시 linearApiKey만 전달하고 apiUrl은 전달하지 않는다 (LINEAR_API_URL 미설정)", async () => {
    const exportConfig = { linear_issue_id: "TEAM-1", summary: "done", actions: ["none"] };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));

    await run();

    expect(mockLinearClientInstances).toHaveLength(1);
    expect(mockLinearClientInstances[0].opts).toEqual({ apiKey: defaultConfig.linearApiKey });
  });

  it("LinearClient 생성 시 LINEAR_API_URL이 설정되면 apiUrl을 함께 전달한다", async () => {
    const configWithApiUrl = createTestAppConfig({ linearApiUrl: "https://linear-proxy.example.com" });
    mockParseConfig.mockReturnValue(configWithApiUrl);
    const exportConfig = { linear_issue_id: "TEAM-1", summary: "done", actions: ["none"] };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));

    await run();

    expect(mockLinearClientInstances).toHaveLength(1);
    expect(mockLinearClientInstances[0].opts).toEqual({
      apiKey: configWithApiUrl.linearApiKey,
      apiUrl: "https://linear-proxy.example.com",
    });
  });

  it("processExport 실패 시 에러를 전파한다", async () => {
    const exportConfig = {
      linear_issue_id: "TEAM-1",
      summary: "done",
      actions: ["none"],
    };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));
    mockProcessExport.mockRejectedValue(new Error("export failed"));

    await expect(run()).rejects.toThrow("export failed");
  });

  it("정상 경로에서 processExport 후 ensureArgoOutput을 호출한다", async () => {
    const exportConfig = {
      linear_issue_id: "TEAM-1",
      summary: "done",
      actions: ["none"],
    };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));

    await run();

    expect(mockEnsureArgoOutput).toHaveBeenCalledWith(
      defaultPaths.exportConfigPath, defaultPaths.argoOutputPath,
    );
  });

  it("정상 경로에서 processExport 후 writeActionResults를 호출한다", async () => {
    const exportConfig = {
      linear_issue_id: "TEAM-1",
      summary: "done",
      actions: ["none"],
    };
    mockExistsSync.mockReturnValue(true);
    mockReadFileSync.mockReturnValue(JSON.stringify(exportConfig));
    mockProcessExport.mockResolvedValue({ pr_url: "https://github.com/org/repo/pull/1" });

    await run();

    expect(mockWriteActionResults).toHaveBeenCalledWith(
      defaultPaths.actionResultsOutputPath,
      { pr_url: "https://github.com/org/repo/pull/1" },
    );
  });
});
