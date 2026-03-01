import { describe, it, expect } from "vitest";
import { getErrorMessage, wrapError, assertValidated } from "../src/errors.js";

describe("getErrorMessage", () => {
  it("returns message from Error", () => {
    expect(getErrorMessage(new Error("fail"))).toBe("fail");
  });

  it("stringifies non-Error values", () => {
    expect(getErrorMessage(42)).toBe("42");
  });
});

describe("wrapError", () => {
  it("wraps error with context prefix", () => {
    const err = wrapError(new Error("original"), "Context");
    expect(err.message).toBe("Context: original");
  });

  it("preserves original error as cause", () => {
    const original = new Error("original");
    const wrapped = wrapError(original, "Context");
    expect(wrapped.cause).toBe(original);
  });

  it("preserves non-Error cause", () => {
    const wrapped = wrapError("string error", "Context");
    expect(wrapped.cause).toBe("string error");
  });
});

describe("assertValidated", () => {
  it("does not throw for truthy values", () => {
    expect(() => assertValidated("value", "field")).not.toThrow();
    expect(() => assertValidated(1, "field")).not.toThrow();
    expect(() => assertValidated({}, "field")).not.toThrow();
  });

  it("throws for null", () => {
    expect(() => assertValidated(null, "field")).toThrow("Bug: field missing");
  });

  it("throws for undefined", () => {
    expect(() => assertValidated(undefined, "field")).toThrow("Bug: field missing");
  });

  it("throws for empty string", () => {
    expect(() => assertValidated("", "field")).toThrow("Bug: field missing");
  });
});
