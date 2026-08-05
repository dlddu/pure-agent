import { vi } from "vitest";
import type { AppConfig } from "./config.js";
import type { ActionContext, ActionDeps } from "./actions/types.js";
import type { ExportConfig } from "./schema.js";
import type { GitDeps } from "./services/git.js";

export function createTestAppConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    workDir: "/test/work",
    tmpDir: "/test/tmp",
    ...overrides,
  };
}

export function createTestActionDeps(overrides: Partial<ActionDeps> = {}): ActionDeps {
  return {
    workDir: "/test/work",
    githubToken: "test-gh-token",
    ...overrides,
  };
}

export function createTestActionContext(
  config: ExportConfig,
  overrides: Partial<ActionContext> = {},
): ActionContext {
  return {
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
