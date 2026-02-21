import { describe, it, expect, vi } from "vitest";
import type { LinearClient } from "@linear/sdk";
import { postLinearComment } from "./linear-comment.js";

describe("postLinearComment", () => {
  function createClient(success: boolean) {
    return {
      createComment: vi.fn().mockResolvedValue({ success }),
    } as unknown as LinearClient;
  }

  it("calls createComment with issueId and body", async () => {
    const client = createClient(true);

    await postLinearComment(client, "TEAM-1", "body text", "summary");

    expect(client.createComment).toHaveBeenCalledWith({
      issueId: "TEAM-1",
      body: "body text",
    });
  });

  it("does not throw when result is successful", async () => {
    await expect(
      postLinearComment(createClient(true), "TEAM-1", "body", "summary"),
    ).resolves.toBeUndefined();
  });

  it("throws with context when result is not successful", async () => {
    await expect(
      postLinearComment(createClient(false), "TEAM-1", "body", "summary"),
    ).rejects.toThrow("Failed to create summary comment on Linear issue");
  });

  it("includes error context in the error message", async () => {
    await expect(
      postLinearComment(createClient(false), "TEAM-1", "body", "PR link"),
    ).rejects.toThrow("Failed to create PR link comment on Linear issue");
  });

  it("wraps thrown errors with context", async () => {
    const client = {
      createComment: vi.fn().mockRejectedValue(new Error("network timeout")),
    } as unknown as LinearClient;

    await expect(
      postLinearComment(client, "TEAM-1", "body", "summary"),
    ).rejects.toThrow("Failed to create summary comment on Linear issue: network timeout");
  });
});
