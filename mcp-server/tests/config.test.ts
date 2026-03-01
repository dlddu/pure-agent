import { describe, it, expect } from "vitest";
import { parseConfig } from "../src/config.js";

describe("parseConfig", () => {
  const validEnv = {
    LINEAR_API_KEY: "lin_api_test123",
    LINEAR_TEAM_ID: "team-uuid",
  };

  it("returns frozen config with defaults for minimal valid env", () => {
    const config = parseConfig(validEnv);
    expect(config.PORT).toBe(8080);
    expect(config.HOST).toBe("0.0.0.0");
    expect(config.MCP_PATH).toBe("/mcp");
    expect(config.WORK_DIR).toBe("/work");
    expect(config.LINEAR_API_KEY).toBe("lin_api_test123");
    expect(config.LINEAR_TEAM_ID).toBe("team-uuid");
    expect(Object.isFrozen(config)).toBe(true);
  });

  it("coerces PORT from string to number", () => {
    const config = parseConfig({ ...validEnv, PORT: "3000" });
    expect(config.PORT).toBe(3000);
  });

  it("uses custom values when provided", () => {
    const config = parseConfig({
      ...validEnv,
      HOST: "127.0.0.1",
      MCP_PATH: "/api/mcp",
      WORK_DIR: "/custom",
    });
    expect(config.HOST).toBe("127.0.0.1");
    expect(config.MCP_PATH).toBe("/api/mcp");
    expect(config.WORK_DIR).toBe("/custom");
  });

  it("throws when LINEAR_API_KEY is missing", () => {
    expect(() => parseConfig({ LINEAR_TEAM_ID: "team" })).toThrow();
  });

  it("throws when LINEAR_API_KEY is empty string", () => {
    expect(() => parseConfig({ LINEAR_API_KEY: "", LINEAR_TEAM_ID: "team" })).toThrow();
  });

  it("throws when LINEAR_TEAM_ID is missing", () => {
    expect(() => parseConfig({ LINEAR_API_KEY: "key" })).toThrow();
  });

  it("returns undefined for optional fields when not provided", () => {
    const config = parseConfig(validEnv);
    expect(config.LINEAR_DEFAULT_PROJECT_ID).toBeUndefined();
    expect(config.LINEAR_DEFAULT_LABEL_ID).toBeUndefined();
  });

  it("populates optional fields when provided", () => {
    const config = parseConfig({
      ...validEnv,
      LINEAR_DEFAULT_PROJECT_ID: "proj-123",
      LINEAR_DEFAULT_LABEL_ID: "label-456",
    });
    expect(config.LINEAR_DEFAULT_PROJECT_ID).toBe("proj-123");
    expect(config.LINEAR_DEFAULT_LABEL_ID).toBe("label-456");
  });

  it("returns undefined for LINEAR_API_URL when not provided", () => {
    const config = parseConfig(validEnv);
    expect(config.LINEAR_API_URL).toBeUndefined();
  });

  it("populates LINEAR_API_URL when provided", () => {
    const config = parseConfig({
      ...validEnv,
      LINEAR_API_URL: "https://linear-proxy.example.com",
    });
    expect(config.LINEAR_API_URL).toBe("https://linear-proxy.example.com");
  });
});
