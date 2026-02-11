import { describe, it, expect, vi, beforeEach } from "vitest";
import type { LinearService } from "../services/linear.js";
import { handleRequestFeature } from "./request-feature.js";

function createMockLinearService() {
  return {
    createFeatureRequest: vi.fn(),
  } as unknown as LinearService;
}

function parseResponseText(result: { content: Array<{ type: string; text: string }> }) {
  return JSON.parse(result.content[0].text);
}

describe("handleRequestFeature", () => {
  let mockLinearService: LinearService;

  beforeEach(() => {
    mockLinearService = createMockLinearService();
  });

  describe("input validation", () => {
    it("rejects when title is missing", async () => {
      const result = await handleRequestFeature(mockLinearService, { reason: "need it" });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when title is shorter than 5 characters", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Hi",
        reason: "need it",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("5");
    });

    it("rejects when title exceeds 200 characters", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "x".repeat(201),
        reason: "need it",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when reason is missing", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Valid title",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when reason is empty string", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Valid title",
        reason: "",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when priority is an invalid enum value", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Valid title",
        reason: "Valid reason",
        priority: "critical",
      });
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await handleRequestFeature(mockLinearService, null);
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
      await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it for X",
        priority: "high",
      });

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith({
        title: "Add new tool",
        reason: "We need it for X",
        priority: "high",
      });
    });

    it('defaults priority to "medium" when not provided', async () => {
      await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it",
      });

      expect(mockLinearService.createFeatureRequest).toHaveBeenCalledWith(
        expect.objectContaining({ priority: "medium" })
      );
    });

    it("returns success response with issue id, identifier, url", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it",
      });

      const parsed = parseResponseText(result);
      expect(parsed.success).toBe(true);
      expect(parsed.issue).toEqual({
        id: "issue-123",
        identifier: "PA-42",
        url: "https://linear.app/issue/PA-42",
      });
    });

    it("does not set isError on success", async () => {
      const result = await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it",
      });

      expect(result.isError).toBeUndefined();
    });
  });

  describe("error handling", () => {
    it("returns isError:true with error message when linearService throws Error", async () => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error("Linear API failed")
      );

      const result = await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it",
      });

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toBe("Linear API failed");
    });

    it('returns "Unknown error occurred" when linearService throws non-Error', async () => {
      (mockLinearService.createFeatureRequest as ReturnType<typeof vi.fn>).mockRejectedValue(
        "string error"
      );

      const result = await handleRequestFeature(mockLinearService, {
        title: "Add new tool",
        reason: "We need it",
      });

      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.error).toBe("Unknown error occurred");
    });
  });
});
