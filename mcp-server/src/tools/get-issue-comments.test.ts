import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ILinearService } from "../services/types.js";
import { getIssueCommentsTool } from "./get-issue-comments.js";
import { parseResponseText, createMockContext } from "../test-utils.js";
import type { McpToolContext } from "./types.js";

describe("getIssueCommentsTool", () => {
  let mockLinearService: ILinearService;
  let context: McpToolContext;

  beforeEach(() => {
    context = createMockContext();
    mockLinearService = context.services.linear;
  });

  describe("input validation", () => {
    it("rejects when issue_id is missing", async () => {
      const result = await getIssueCommentsTool.handler({}, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when issue_id is empty string", async () => {
      const result = await getIssueCommentsTool.handler({ issue_id: "" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await getIssueCommentsTool.handler(null, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  describe("successful comments retrieval", () => {
    it("calls linearService.getIssueComments with validated issue_id", async () => {
      await getIssueCommentsTool.handler({ issue_id: "PA-42" }, context);

      expect(mockLinearService.getIssueComments).toHaveBeenCalledWith("PA-42");
    });

    it("returns success response with comments array", async () => {
      const result = await getIssueCommentsTool.handler({ issue_id: "PA-1" }, context);

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.comments).toHaveLength(1);
      expect(parsed.comments[0].id).toBe("comment-1");
      expect(parsed.comments[0].body).toBe("This is a comment");
    });

    it("returns empty comments array when issue has no comments", async () => {
      (mockLinearService.getIssueComments as ReturnType<typeof vi.fn>).mockResolvedValue([]);

      const result = await getIssueCommentsTool.handler({ issue_id: "PA-1" }, context);

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.comments).toEqual([]);
    });

    it("does not set isError on success", async () => {
      const result = await getIssueCommentsTool.handler({ issue_id: "PA-1" }, context);

      expect(result.isError).toBeUndefined();
    });
  });

  describe("error handling", () => {
    it("returns isError:true with error message when linearService throws Error", async () => {
      (mockLinearService.getIssueComments as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Issue not found"),
      );

      const result = await getIssueCommentsTool.handler({ issue_id: "PA-999" }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toBe("Issue not found");
    });

    it('returns "Unknown error occurred" when linearService throws non-Error', async () => {
      (mockLinearService.getIssueComments as ReturnType<typeof vi.fn>).mockRejectedValue(
        "string error",
      );

      const result = await getIssueCommentsTool.handler({ issue_id: "PA-1" }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toBe("Unknown error occurred");
    });
  });
});
