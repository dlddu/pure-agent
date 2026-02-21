import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ILinearService } from "../services/types.js";
import { parseResponseText, createMockContext } from "../test-utils.js";
import type { McpToolContext } from "./types.js";
import { getIssueTool } from "./get-issue.js";

describe("getIssueTool", () => {
  let mockLinearService: ILinearService;
  let context: McpToolContext;

  beforeEach(() => {
    context = createMockContext();
    mockLinearService = context.services.linear;
  });

  describe("input validation", () => {
    it("rejects when issue_id is missing", async () => {
      const result = await getIssueTool.handler({}, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when issue_id is empty string", async () => {
      const result = await getIssueTool.handler({ issue_id: "" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await getIssueTool.handler(null, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  describe("successful issue retrieval", () => {
    it("calls linearService.getIssue with validated issue_id", async () => {
      await getIssueTool.handler({ issue_id: "PA-42" }, context);

      expect(mockLinearService.getIssue).toHaveBeenCalledWith("PA-42");
    });

    it("returns success response with full issue data", async () => {
      const result = await getIssueTool.handler({ issue_id: "PA-1" }, context);

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.issue.id).toBe("issue-1");
      expect(parsed.issue.identifier).toBe("PA-1");
      expect(parsed.issue.title).toBe("Test Issue");
      expect(parsed.issue.state).toEqual({ name: "In Progress", type: "started" });
      expect(parsed.issue.labels).toHaveLength(1);
    });

    it("does not set isError on success", async () => {
      const result = await getIssueTool.handler({ issue_id: "PA-1" }, context);

      expect(result.isError).toBeUndefined();
    });
  });

  describe("error handling", () => {
    it("returns isError:true with error message when linearService throws Error", async () => {
      (mockLinearService.getIssue as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Issue not found"),
      );

      const result = await getIssueTool.handler({ issue_id: "PA-999" }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toBe("Issue not found");
    });

    it('returns "Unknown error occurred" when linearService throws non-Error', async () => {
      (mockLinearService.getIssue as ReturnType<typeof vi.fn>).mockRejectedValue("string error");

      const result = await getIssueTool.handler({ issue_id: "PA-1" }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toBe("Unknown error occurred");
    });
  });

  describe("response metadata", () => {
    it("sets _meta.issueId to the fetched issue ID", async () => {
      const result = await getIssueTool.handler({ issue_id: "PA-1" }, context);

      expect(result._meta).toEqual({ issueId: "issue-1" });
    });

  });
});
