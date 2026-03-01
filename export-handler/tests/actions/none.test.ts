import { describe, it, expect } from "vitest";
import { noneHandler } from "../../src/actions/none.js";
import type { ActionContext } from "../../src/actions/types.js";

describe("noneHandler", () => {
  const ctx = {} as ActionContext;

  it("validate does not throw", () => {
    expect(() => noneHandler.validate(ctx)).not.toThrow();
  });

  it("execute resolves with empty result", async () => {
    await expect(noneHandler.execute(ctx)).resolves.toEqual({});
  });
});
