import { vi } from "vitest";
import type { LinearClient } from "@linear/sdk";
import type { AppConfig } from "../src/config.js";
import type { ActionContext, ActionDeps } from "../src/actions/types.js";
import type { ExportConfig } from "../src/schema.js";
import type { GitDeps } from "../src/services/git.js";

export function createTestAppConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    workDir: "/test/work",
    tmpDir: "/test/tmp",
    linearApiKey: "test-api-key",
    ...overrides,
  };
}

export function createTestActionDeps(overrides: Partial<ActionDeps> = {}): ActionDeps {
  return {
    workDir: "/test/work",
    zipOutputPath: "/test/tmp/workspace.zip",
    githubToken: "test-gh-token",
    ...overrides,
  };
}

export function createMockLinearClient(
  overrides: Partial<Record<"createComment" | "fileUpload", unknown>> = {},
): LinearClient {
  return {
    createComment: vi.fn().mockResolvedValue({ success: true }),
    fileUpload: vi.fn(),
    ...overrides,
  } as unknown as LinearClient;
}

export function createTestActionContext(
  config: ExportConfig,
  overrides: Partial<ActionContext> = {},
): ActionContext {
  return {
    linearClient: createMockLinearClient(),
    issueId: config.linear_issue_id,
    config,
    ...createTestActionDeps(),
    ...overrides,
  };
}

export function createMockGitDeps(
  overrides: Partial<GitDeps> = {},
): GitDeps {
  return {
    execFileSync: vi.fn().mockReturnValue(Buffer.from("")),
    existsSync: vi.fn().mockReturnValue(true),
    ...overrides,
  };
}
