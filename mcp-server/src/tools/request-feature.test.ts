import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ILinearService } from "../services/types.js";
import { parseResponseText, createMockContext } from "../test-utils.js";
import type { McpToolContext } from "./types.js";
import { requestFeatureTool } from "./request-feature.js";

describe("requestFeatureTool", () => {
  let mockLinearService: ILinearService;
  let context: McpToolContext;

  beforeEach(() => {
    context = createMockContext();
    mockLinearService = context.services.linear;
  });

  describe("input validation", () => {
    it("rejects when title is missing", async () => {
      const result = await requestFeatureTool.handler({ reason: "need it" }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when title is shorter than 5 characters", async () => {
      const result = await requestFeatureTool.handler({
        title: "Hi",
        reason: "need it",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("5");
    });

    it("rejects when title exceeds 200 characters", async () => {
      const result = await requestFeatureTool.handler({
        title: "x".repeat(201),
        reason: "need it",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when reason is missing", async () => {
      const result = await requestFeatureTool.handler({
        title: "Valid title",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when reason is empty string", async () => {
      const result = await requestFeatureTool.handler({
        title: "Valid title",
        reason: "",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when priority is an invalid enum value", async () => {
      const result = await requestFeatureTool.handler({
        title: "Valid title",
        reason: "Valid reason",
        priority: "critical",
      }, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await requestFeatureTool.handler(null, context);
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  describe("successful feature request", () => {
    beforeEach(() => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockResolvedValue({
        issueId: "issue-123",
        issueIdentifier: "PA-42",
        issueUrl: "https://linear.app/issue/PA-42",
      });
    });

    it("calls linearService.createFeatureRequest with validated data", async () => {
      await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it for X",
        priority: "high",
      }, context);

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith({
        title: "Add new tool",
        reason: "We need it for X",
        priority: "high",
      });
    });

    it('defaults priority to "medium" when not provided', async () => {
      await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it",
      }, context);

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith(
        expect.objectContaining({ priority: "medium" })
      );
    });

    it("returns success response with issue id, identifier, url", async () => {
      const result = await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it",
      }, context);

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.issue).toEqual({
        id: "issue-123",
        identifier: "PA-42",
        url: "https://linear.app/issue/PA-42",
      });
    });

    it("does not set isError on success", async () => {
      const result = await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it",
      }, context);

      expect(result.isError).toBeUndefined();
    });
  });

  describe("error handling", () => {
    it("returns isError:true with error message when linearService throws Error", async () => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Linear API failed")
      );

      const result = await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it",
      }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toBe("Linear API failed");
    });

    it('returns "Unknown error occurred" when linearService throws non-Error', async () => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockRejectedValue(
        "string error"
      );

      const result = await requestFeatureTool.handler({
        title: "Add new tool",
        reason: "We need it",
      }, context);

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toBe("Unknown error occurred");
    });
  });

  describe("response metadata", () => {
    const validArgs = { title: "Add new tool", reason: "We need it" };

    beforeEach(() => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockResolvedValue({
        issueId: "issue-123",
        issueIdentifier: "PA-42",
        issueUrl: "https://linear.app/issue/PA-42",
      });
    });

    it("sets _meta.issueId to the created issue ID", async () => {
      const result = await requestFeatureTool.handler(validArgs, context);

      expect(result._meta).toEqual({ issueId: "issue-123" });
    });

  });
});
