import { describe, it, expect, vi, beforeEach } from "vitest";
import { LinearService } from "./linear.js";
import type { LinearClientLike } from "./types.js";

function createMockClient() {
  return {
    createIssue: vi.fn(),
    issue: vi.fn(),
    createComment: vi.fn(),
  } satisfies Record<keyof LinearClientLike, ReturnType<typeof vi.fn>>;
}

function mockIssuePayload(issue: { id: string; url: string; identifier: string } | undefined) {
  return { issue: Promise.resolve(issue) };
}

function mockCommentNode(overrides?: Record<string, unknown>) {
  return {
    id: "comment-1",
    body: "A comment",
    user: Promise.resolve({ id: "user-1", name: "Commenter", email: "c@example.com" }),
    createdAt: new Date("2025-01-01"),
    updatedAt: new Date("2025-01-01"),
    url: "https://linear.app/comment/1",
    ...overrides,
  };
}

describe("LinearService", () => {
  let service: LinearService;
  let mockClient: ReturnType<typeof createMockClient>;

  beforeEach(() => {
    mockClient = createMockClient();
    service = new LinearService({
      client: mockClient,
      teamId: "test-team-id",
    });
  });

  describe("createFeatureRequest", () => {
    describe("priority mapping", () => {
      const priorityCases: Array<[string, number]> = [
        ["urgent", 1],
        ["high", 2],
        ["medium", 3],
        ["low", 4],
        ["none", 0],
      ];

      it.each(priorityCases)('maps "%s" to %d', async (priority, expected) => {
        mockClient.createIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );

        await service.createFeatureRequest({
          title: "Test",
          reason: "Test reason",
          priority: priority as "urgent" | "high" | "medium" | "low" | "none",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({ priority: expected })
        );
      });

      it("defaults to medium (3) when priority is not provided", async () => {
        mockClient.createIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );

        await service.createFeatureRequest({
          title: "Test",
          reason: "Test reason",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({ priority: 3 })
        );
      });
    });

    describe("issue creation payload", () => {
      beforeEach(() => {
        mockClient.createIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );
      });

      it('formats description with "## Reason" prefix', async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Because we need it",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({
            description: "## Reason\n\nBecause we need it",
          })
        );
      });

      it("passes teamId from constructor", async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({ teamId: "test-team-id" })
        );
      });

      it("includes projectId when defaultProjectId is set", async () => {
        const serviceWithProject = new LinearService({
          client: mockClient,
          teamId: "team",
          defaultProjectId: "project-123",
        });

        await serviceWithProject.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({ projectId: "project-123" })
        );
      });

      it("does NOT include projectId when defaultProjectId is not set", async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        const callArgs = mockClient.createIssue.mock.calls[0][0];
        expect(callArgs).not.toHaveProperty("projectId");
      });

      it("includes labelIds when defaultLabelId is set", async () => {
        const serviceWithLabel = new LinearService({
          client: mockClient,
          teamId: "team",
          defaultLabelId: "label-456",
        });

        await serviceWithLabel.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(mockClient.createIssue).toHaveBeenCalledWith(
          expect.objectContaining({ labelIds: ["label-456"] })
        );
      });

      it("does NOT include labelIds when defaultLabelId is not set", async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        const callArgs = mockClient.createIssue.mock.calls[0][0];
        expect(callArgs).not.toHaveProperty("labelIds");
      });
    });

    describe("return value", () => {
      it("returns issueId, issueUrl, issueIdentifier from the created issue", async () => {
        mockClient.createIssue.mockResolvedValue(
          mockIssuePayload({
            id: "issue-id-123",
            url: "https://linear.app/issue/ID-42",
            identifier: "ID-42",
          })
        );

        const result = await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(result).toEqual({
          issueId: "issue-id-123",
          issueUrl: "https://linear.app/issue/ID-42",
          issueIdentifier: "ID-42",
        });
      });
    });

    describe("error cases", () => {
      it('throws "Failed to create Linear issue" when issue resolves to undefined', async () => {
        mockClient.createIssue.mockResolvedValue(mockIssuePayload(undefined));

        await expect(
          service.createFeatureRequest({ title: "Test", reason: "Reason" })
        ).rejects.toThrow("Failed to create Linear issue");
      });

      it("propagates errors from the Linear API", async () => {
        mockClient.createIssue.mockRejectedValue(new Error("API rate limit exceeded"));

        await expect(
          service.createFeatureRequest({ title: "Test", reason: "Reason" })
        ).rejects.toThrow("API rate limit exceeded");
      });
    });
  });

  describe("getIssue", () => {
    function mockIssueData(overrides?: Record<string, unknown>) {
      return {
        id: "issue-id",
        identifier: "PA-42",
        title: "Fix the bug",
        description: "It is broken",
        priority: 2,
        priorityLabel: "High",
        url: "https://linear.app/issue/PA-42",
        createdAt: new Date("2025-01-01"),
        updatedAt: new Date("2025-01-02"),
        dueDate: null,
        estimate: 3,
        state: Promise.resolve({ name: "In Progress", type: "started" }),
        assignee: Promise.resolve({ id: "user-1", name: "Test User", email: "test@example.com" }),
        labels: vi.fn().mockResolvedValue({
          nodes: [{ id: "label-1", name: "Bug", color: "#ff0000" }],
        }),
        ...overrides,
      };
    }

    it("returns issue data with state, assignee, and labels resolved", async () => {
      mockClient.issue.mockResolvedValue(mockIssueData());

      const result = await service.getIssue("PA-42");

      expect(mockClient.issue).toHaveBeenCalledWith("PA-42");
      expect(result.id).toBe("issue-id");
      expect(result.identifier).toBe("PA-42");
      expect(result.title).toBe("Fix the bug");
      expect(result.description).toBe("It is broken");
      expect(result.state).toEqual({ name: "In Progress", type: "started" });
      expect(result.priority).toBe(2);
      expect(result.priorityLabel).toBe("High");
      expect(result.assignee).toEqual({ id: "user-1", name: "Test User", email: "test@example.com" });
      expect(result.labels).toEqual([{ id: "label-1", name: "Bug", color: "#ff0000" }]);
      expect(result.url).toBe("https://linear.app/issue/PA-42");
      expect(result.createdAt).toBe("2025-01-01T00:00:00.000Z");
      expect(result.updatedAt).toBe("2025-01-02T00:00:00.000Z");
      expect(result.estimate).toBe(3);
    });

    it("returns undefined assignee when issue is unassigned", async () => {
      mockClient.issue.mockResolvedValue(mockIssueData({
        assignee: Promise.resolve(undefined),
      }));

      const result = await service.getIssue("PA-43");
      expect(result.assignee).toBeUndefined();
    });

    it("returns empty labels array when issue has no labels", async () => {
      mockClient.issue.mockResolvedValue(mockIssueData({
        labels: vi.fn().mockResolvedValue({ nodes: [] }),
      }));

      const result = await service.getIssue("PA-43");
      expect(result.labels).toEqual([]);
    });

    it("returns undefined description when issue has no description", async () => {
      mockClient.issue.mockResolvedValue(mockIssueData({
        description: undefined,
      }));

      const result = await service.getIssue("PA-43");
      expect(result.description).toBeUndefined();
    });

    it('throws "Failed to fetch issue state" when state resolves to undefined', async () => {
      mockClient.issue.mockResolvedValue(mockIssueData({
        state: Promise.resolve(undefined),
      }));

      await expect(service.getIssue("PA-43")).rejects.toThrow("Failed to fetch issue state");
    });

    it("propagates errors from the Linear API", async () => {
      mockClient.issue.mockRejectedValue(new Error("Not found"));

      await expect(service.getIssue("nonexistent")).rejects.toThrow("Not found");
    });
  });

  describe("getIssueComments", () => {
    it("returns comments with user info resolved", async () => {
      mockClient.issue.mockResolvedValue({
        comments: vi.fn().mockResolvedValue({
          nodes: [mockCommentNode()],
        }),
      });

      const result = await service.getIssueComments("PA-42");

      expect(mockClient.issue).toHaveBeenCalledWith("PA-42");
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe("comment-1");
      expect(result[0].body).toBe("A comment");
      expect(result[0].user).toEqual({ id: "user-1", name: "Commenter", email: "c@example.com" });
      expect(result[0].createdAt).toBe("2025-01-01T00:00:00.000Z");
      expect(result[0].url).toBe("https://linear.app/comment/1");
    });

    it("returns empty array when issue has no comments", async () => {
      mockClient.issue.mockResolvedValue({
        comments: vi.fn().mockResolvedValue({ nodes: [] }),
      });

      const result = await service.getIssueComments("PA-42");
      expect(result).toEqual([]);
    });

    it("handles comments with no user", async () => {
      mockClient.issue.mockResolvedValue({
        comments: vi.fn().mockResolvedValue({
          nodes: [mockCommentNode({ user: Promise.resolve(undefined) })],
        }),
      });

      const result = await service.getIssueComments("PA-42");
      expect(result[0].user).toBeUndefined();
    });

    it("propagates errors from the Linear API", async () => {
      mockClient.issue.mockRejectedValue(new Error("API error"));

      await expect(service.getIssueComments("bad-id")).rejects.toThrow("API error");
    });
  });

  describe("createComment", () => {
    it("calls client.createComment with issueId and body", async () => {
      mockClient.createComment.mockResolvedValue({
        success: true,
        comment: Promise.resolve({ id: "comment-abc" }),
      });

      await service.createComment("issue-123", "Hello world");

      expect(mockClient.createComment).toHaveBeenCalledWith({
        issueId: "issue-123",
        body: "Hello world",
      });
    });

    it("returns commentId from the created comment", async () => {
      mockClient.createComment.mockResolvedValue({
        success: true,
        comment: Promise.resolve({ id: "comment-abc" }),
      });

      const result = await service.createComment("issue-123", "Hello world");

      expect(result).toEqual({ commentId: "comment-abc" });
    });

    it("throws when result.success is false", async () => {
      mockClient.createComment.mockResolvedValue({ success: false });

      await expect(
        service.createComment("issue-123", "Hello world")
      ).rejects.toThrow("Failed to create comment on Linear issue");
    });

    it("throws when comment resolves to null", async () => {
      mockClient.createComment.mockResolvedValue({
        success: true,
        comment: Promise.resolve(null),
      });

      await expect(
        service.createComment("issue-123", "Hello world")
      ).rejects.toThrow("Comment was created but could not be retrieved");
    });

    it("propagates errors from the Linear API", async () => {
      mockClient.createComment.mockRejectedValue(new Error("Rate limited"));

      await expect(
        service.createComment("issue-123", "Hello world")
      ).rejects.toThrow("Rate limited");
    });
  });
});
