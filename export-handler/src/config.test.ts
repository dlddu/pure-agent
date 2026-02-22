import { describe, it, expect } from "vitest";
import { parseConfig, derivePaths, deriveFallbackArgoPaths } from "./config.js";
import { createTestAppConfig } from "./test-helpers.js";

describe("parseConfig", () => {
  const validEnv = {
    LINEAR_API_KEY: "lin_key",
  };

  it("returns AppConfig with defaults for optional env vars", () => {
    const config = parseConfig(validEnv);
    expect(config.workDir).toBe("/work");
    expect(config.tmpDir).toBe("/tmp");
    expect(config.linearApiKey).toBe("lin_key");
  });

  it("returns frozen object", () => {
    expect(Object.isFrozen(parseConfig(validEnv))).toBe(true);
  });

  it("uses custom WORK_DIR and TMP_DIR when provided", () => {
    const config = parseConfig({ ...validEnv, WORK_DIR: "/custom/work", TMP_DIR: "/custom/tmp" });
    expect(config.workDir).toBe("/custom/work");
    expect(config.tmpDir).toBe("/custom/tmp");
  });

  it("throws when LINEAR_API_KEY is missing", () => {
    expect(() => parseConfig({})).toThrow();
  });

  it("throws when LINEAR_API_KEY is empty", () => {
    expect(() => parseConfig({ LINEAR_API_KEY: "" })).toThrow();
  });

  it("maps optional GITHUB_TOKEN", () => {
    const config = parseConfig({ ...validEnv, GITHUB_TOKEN: "gh_tok" });
    expect(config.githubToken).toBe("gh_tok");
  });

  it("leaves optional fields undefined when not provided", () => {
    const config = parseConfig(validEnv);
    expect(config.githubToken).toBeUndefined();
  });

  it("returns undefined for linearApiUrl when LINEAR_API_URL is not provided", () => {
    const config = parseConfig(validEnv);
    expect(config.linearApiUrl).toBeUndefined();
  });

  it("maps LINEAR_API_URL to linearApiUrl when provided", () => {
    const config = parseConfig({ ...validEnv, LINEAR_API_URL: "https://linear-proxy.example.com" });
    expect(config.linearApiUrl).toBe("https://linear-proxy.example.com");
  });
});

describe("derivePaths", () => {
  it("derives all paths from config directories", () => {
    const config = createTestAppConfig({ workDir: "/w", tmpDir: "/t" });
    const paths = derivePaths(config);
    expect(paths.exportConfigPath).toBe("/w/export_config.json");
    expect(paths.argoOutputPath).toBe("/t/export_config.json");
    expect(paths.actionResultsOutputPath).toBe("/t/action_results.json");
    expect(paths.zipOutputPath).toBe("/t/workspace.zip");
  });

  it("uses default paths from createTestAppConfig", () => {
    const config = createTestAppConfig();
    const paths = derivePaths(config);
    expect(paths.exportConfigPath).toBe("/test/work/export_config.json");
    expect(paths.argoOutputPath).toBe("/test/tmp/export_config.json");
  });
});

describe("deriveFallbackArgoPaths", () => {
  it("uses default directories when env vars are missing", () => {
    const paths = deriveFallbackArgoPaths({});
    expect(paths.exportConfigPath).toBe("/work/export_config.json");
    expect(paths.argoOutputPath).toBe("/tmp/export_config.json");
  });

  it("uses provided WORK_DIR and TMP_DIR", () => {
    const paths = deriveFallbackArgoPaths({ WORK_DIR: "/custom", TMP_DIR: "/t" });
    expect(paths.exportConfigPath).toBe("/custom/export_config.json");
    expect(paths.argoOutputPath).toBe("/t/export_config.json");
  });
});
