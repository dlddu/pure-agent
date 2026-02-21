import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Logger reads LOG_FORMAT and DEBUG at module load time via top-level const,
// so we must reset modules between groups to test different env combos.

describe("createLogger (text format)", () => {
  let createLogger: typeof import("./logger.js").createLogger;

  beforeEach(async () => {
    delete process.env.LOG_FORMAT;
    delete process.env.DEBUG;
    vi.resetModules();
    const mod = await import("./logger.js");
    createLogger = mod.createLogger;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("info writes to console.log with component prefix", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("test");
    log.info("hello");
    expect(spy).toHaveBeenCalledWith("[test]", "hello");
  });

  it("warn writes to console.warn with component prefix", () => {
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const log = createLogger("test");
    log.warn("warning");
    expect(spy).toHaveBeenCalledWith("[test]", "warning");
  });

  it("error writes to console.error with component prefix", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const log = createLogger("test");
    log.error("fail");
    expect(spy).toHaveBeenCalledWith("[test]", "fail");
  });

  it("debug does not write when DEBUG is not set", () => {
    const spy = vi.spyOn(console, "debug").mockImplementation(() => {});
    const log = createLogger("test");
    log.debug("hidden");
    expect(spy).not.toHaveBeenCalled();
  });

  it("passes extra args through", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("test");
    log.info("msg", { key: "value" }, 42);
    expect(spy).toHaveBeenCalledWith("[test]", "msg", { key: "value" }, 42);
  });
});

describe("createLogger (text format with DEBUG)", () => {
  let createLogger: typeof import("./logger.js").createLogger;

  beforeEach(async () => {
    delete process.env.LOG_FORMAT;
    process.env.DEBUG = "1";
    vi.resetModules();
    const mod = await import("./logger.js");
    createLogger = mod.createLogger;
  });

  afterEach(() => {
    delete process.env.DEBUG;
    vi.restoreAllMocks();
  });

  it("debug writes to console.debug when DEBUG is set", () => {
    const spy = vi.spyOn(console, "debug").mockImplementation(() => {});
    const log = createLogger("test");
    log.debug("visible");
    expect(spy).toHaveBeenCalledWith("[test]", "visible");
  });
});

describe("createLogger (JSON format)", () => {
  let createLogger: typeof import("./logger.js").createLogger;

  beforeEach(async () => {
    process.env.LOG_FORMAT = "json";
    delete process.env.DEBUG;
    vi.resetModules();
    const mod = await import("./logger.js");
    createLogger = mod.createLogger;
  });

  afterEach(() => {
    delete process.env.LOG_FORMAT;
    vi.restoreAllMocks();
  });

  it("info outputs valid JSON with required fields", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("comp");
    log.info("test message");

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.level).toBe("info");
    expect(parsed.component).toBe("comp");
    expect(parsed.message).toBe("test message");
    expect(parsed.timestamp).toBeDefined();
    expect(new Date(parsed.timestamp).toISOString()).toBe(parsed.timestamp);
    expect(parsed.data).toBeUndefined();
  });

  it("warn outputs JSON to console.warn", () => {
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const log = createLogger("comp");
    log.warn("warning");

    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.level).toBe("warn");
  });

  it("error outputs JSON to console.error", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const log = createLogger("comp");
    log.error("fail");

    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.level).toBe("error");
  });

  it("includes single extra arg as data field directly", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("comp");
    log.info("msg", { key: "value" });

    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.data).toEqual({ key: "value" });
  });

  it("includes multiple extra args as data array", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("comp");
    log.info("msg", "a", 42);

    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.data).toEqual(["a", 42]);
  });

  it("debug does not write when DEBUG is not set", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("comp");
    log.debug("hidden");
    expect(logSpy).not.toHaveBeenCalled();
  });
});

describe("createLogger (JSON format with DEBUG)", () => {
  let createLogger: typeof import("./logger.js").createLogger;

  beforeEach(async () => {
    process.env.LOG_FORMAT = "json";
    process.env.DEBUG = "1";
    vi.resetModules();
    const mod = await import("./logger.js");
    createLogger = mod.createLogger;
  });

  afterEach(() => {
    delete process.env.LOG_FORMAT;
    delete process.env.DEBUG;
    vi.restoreAllMocks();
  });

  it("debug outputs JSON when DEBUG is set", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const log = createLogger("comp");
    log.debug("visible");

    const parsed = JSON.parse(spy.mock.calls[0][0] as string);
    expect(parsed.level).toBe("debug");
    expect(parsed.message).toBe("visible");
  });
});
