import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockCreateIssue } = vi.hoisted(() => ({
  mockCreateIssue: vi.fn(),
}));

vi.mock("@linear/sdk", () => ({
  LinearClient: class MockLinearClient {
    createIssue = mockCreateIssue;
  },
}));

import { LinearService } from "./linear.js";

function mockIssuePayload(issue: { id: string; url: string; identifier: string } | undefined) {
  return { issue: Promise.resolve(issue) };
}

describe("LinearService", () => {
  let service: LinearService;

  beforeEach(() => {
    service = new LinearService({
      apiKey: "test-api-key",
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
        mockCreateIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );

        await service.createFeatureRequest({
          title: "Test",
          reason: "Test reason",
          priority: priority as "urgent" | "high" | "medium" | "low" | "none",
        });

        expect(mockCreateIssue).toHaveBeenCalledWith(
          expect.objectContaining({ priority: expected })
        );
      });

      it("defaults to medium (3) when priority is not provided", async () => {
        mockCreateIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );

        await service.createFeatureRequest({
          title: "Test",
          reason: "Test reason",
        });

        expect(mockCreateIssue).toHaveBeenCalledWith(
          expect.objectContaining({ priority: 3 })
        );
      });
    });

    describe("issue creation payload", () => {
      beforeEach(() => {
        mockCreateIssue.mockResolvedValue(
          mockIssuePayload({ id: "id", url: "url", identifier: "ID-1" })
        );
      });

      it('formats description with "## Reason" prefix', async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Because we need it",
        });

        expect(mockCreateIssue).toHaveBeenCalledWith(
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

        expect(mockCreateIssue).toHaveBeenCalledWith(
          expect.objectContaining({ teamId: "test-team-id" })
        );
      });

      it("includes projectId when defaultProjectId is set", async () => {
        const serviceWithProject = new LinearService({
          apiKey: "key",
          teamId: "team",
          defaultProjectId: "project-123",
        });

        await serviceWithProject.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(mockCreateIssue).toHaveBeenCalledWith(
          expect.objectContaining({ projectId: "project-123" })
        );
      });

      it("does NOT include projectId when defaultProjectId is not set", async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        const callArgs = mockCreateIssue.mock.calls[0][0];
        expect(callArgs).not.toHaveProperty("projectId");
      });

      it("includes labelIds when defaultLabelId is set", async () => {
        const serviceWithLabel = new LinearService({
          apiKey: "key",
          teamId: "team",
          defaultLabelId: "label-456",
        });

        await serviceWithLabel.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        expect(mockCreateIssue).toHaveBeenCalledWith(
          expect.objectContaining({ labelIds: ["label-456"] })
        );
      });

      it("does NOT include labelIds when defaultLabelId is not set", async () => {
        await service.createFeatureRequest({
          title: "Test",
          reason: "Reason",
        });

        const callArgs = mockCreateIssue.mock.calls[0][0];
        expect(callArgs).not.toHaveProperty("labelIds");
      });
    });

    describe("return value", () => {
      it("returns issueId, issueUrl, issueIdentifier from the created issue", async () => {
        mockCreateIssue.mockResolvedValue(
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
        mockCreateIssue.mockResolvedValue(mockIssuePayload(undefined));

        await expect(
          service.createFeatureRequest({ title: "Test", reason: "Reason" })
        ).rejects.toThrow("Failed to create Linear issue");
      });

      it("propagates errors from the Linear API", async () => {
        mockCreateIssue.mockRejectedValue(new Error("API rate limit exceeded"));

        await expect(
          service.createFeatureRequest({ title: "Test", reason: "Reason" })
        ).rejects.toThrow("API rate limit exceeded");
      });
    });
  });
});
