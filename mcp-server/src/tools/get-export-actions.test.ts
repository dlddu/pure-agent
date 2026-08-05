import { describe, it, expect } from "vitest";
import { parseResponseText, createMockContext } from "../test-utils.js";
import { getExportActionsTool } from "./get-export-actions.js";

const dummyContext = createMockContext();

describe("getExportActionsTool", () => {
  it("returns all 2 export action types", async () => {
    const result = await getExportActionsTool.handler({}, dummyContext);
    const parsed = parseResponseText(result);

    expect(parsed.success).toBe(true);
    expect(parsed.actions).toHaveLength(2);
    const types = parsed.actions.map((a: { type: string }) => a.type);
    expect(types).toEqual(["none", "create_pr"]);
  });

  it("does not set isError on the response", async () => {
    const result = await getExportActionsTool.handler({}, dummyContext);
    expect(result).not.toHaveProperty("isError");
  });

  it("includes correct required_fields for each action", async () => {
    const result = await getExportActionsTool.handler({}, dummyContext);
    const parsed = parseResponseText(result);

    const prAction = parsed.actions.find((a: { type: string }) => a.type === "create_pr");
    expect(prAction.required_fields).toEqual(
      expect.arrayContaining(["pr.title", "pr.body", "pr.branch", "pr.repo", "pr.repo_path"])
    );

    const noneAction = parsed.actions.find((a: { type: string }) => a.type === "none");
    expect(noneAction.required_fields).toHaveLength(0);

  });
});
