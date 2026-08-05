import { describe, it, expect } from "vitest";
import { parseConfig } from "./config.js";

describe("parseConfig", () => {
  const validEnv = {};

  it("returns frozen config with defaults for minimal valid env", () => {
    const config = parseConfig(validEnv);
    expect(config.PORT).toBe(8080);
    expect(config.HOST).toBe("0.0.0.0");
    expect(config.MCP_PATH).toBe("/mcp");
    expect(config.WORK_DIR).toBe("/work");
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

  it("throws when GATEKEEPER_URL is missing", () => {
    expect(() =>
      parseConfig({
        ...validEnv,
        GATEKEEPER_API_KEY: "gk_api_test123",
        // GATEKEEPER_URL 누락
      }),
    ).toThrow();
  });

  it("throws when GATEKEEPER_API_KEY is missing", () => {
    expect(() =>
      parseConfig({
        ...validEnv,
        GATEKEEPER_URL: "https://gatekeeper.example.com",
        // GATEKEEPER_API_KEY 누락
      }),
    ).toThrow();
  });

  it("uses default values for GATEKEEPER_POLL_INTERVAL_MS and GATEKEEPER_TIMEOUT_MS", () => {
    const config = parseConfig({
      ...validEnv,
      GATEKEEPER_URL: "https://gatekeeper.example.com",
      GATEKEEPER_API_KEY: "gk_api_test123",
    });
    expect(config.GATEKEEPER_POLL_INTERVAL_MS).toBe(3000);
    expect(config.GATEKEEPER_TIMEOUT_MS).toBe(600000);
  });

  it("parses custom polling configuration values", () => {
    const config = parseConfig({
      ...validEnv,
      GATEKEEPER_URL: "https://gatekeeper.example.com",
      GATEKEEPER_API_KEY: "gk_api_test123",
      GATEKEEPER_POLL_INTERVAL_MS: "5000",
      GATEKEEPER_TIMEOUT_MS: "60000",
    });
    expect(config.GATEKEEPER_POLL_INTERVAL_MS).toBe(5000);
    expect(config.GATEKEEPER_TIMEOUT_MS).toBe(60000);
  });
});
