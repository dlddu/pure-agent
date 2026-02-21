import { describe, it, expect, vi, beforeEach } from "vitest";
import { sessionCommentHook, runPostToolHooks, type PostToolHook } from "./post-tool-hooks.js";
import { createMockContext } from "../test-utils.js";
import type { McpToolContext, McpToolResponse, McpToolMeta } from "../tools/types.js";

describe("sessionCommentHook", () => {
  let context: McpToolContext;

  beforeEach(() => {
    context = createMockContext();
  });

  it("posts session comment when response has issueId and session exists", async () => {
    (context.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-123");

    const response: McpToolResponse & { _meta?: McpToolMeta } = {
      content: [{ type: "text", text: "{}" }],
      _meta: { issueId: "issue-1" },
    };

    await sessionCommentHook(response, context);

    expect(context.services.session.readSessionId).toHaveBeenCalled();
    expect(context.services.linear.createComment).toHaveBeenCalledWith(
      "issue-1",
      expect.stringContaining("sess-123"),
    );
  });

  it("skips when no issueId in _meta", async () => {
    const response: McpToolResponse = {
      content: [{ type: "text", text: "{}" }],
    };

    await sessionCommentHook(response, context);

    expect(context.services.session.readSessionId).not.toHaveBeenCalled();
  });

  it("skips when response is an error", async () => {
    const response: McpToolResponse & { _meta?: McpToolMeta } = {
      content: [{ type: "text", text: "{}" }],
      isError: true,
      _meta: { issueId: "issue-1" },
    };

    await sessionCommentHook(response, context);

    expect(context.services.session.readSessionId).not.toHaveBeenCalled();
  });

  it("skips when no session ID available", async () => {
    const response: McpToolResponse & { _meta?: McpToolMeta } = {
      content: [{ type: "text", text: "{}" }],
      _meta: { issueId: "issue-1" },
    };

    await sessionCommentHook(response, context);

    expect(context.services.session.readSessionId).toHaveBeenCalled();
    expect(context.services.linear.createComment).not.toHaveBeenCalled();
  });

  it("swallows createComment errors silently", async () => {
    (context.services.session.readSessionId as ReturnType<typeof vi.fn>).mockResolvedValue("sess-123");
    (context.services.linear.createComment as ReturnType<typeof vi.fn>).mockRejectedValue(
      new Error("Linear API error"),
    );

    const response: McpToolResponse & { _meta?: McpToolMeta } = {
      content: [{ type: "text", text: "{}" }],
      _meta: { issueId: "issue-1" },
    };

    await expect(sessionCommentHook(response, context)).resolves.toBeUndefined();
  });
});

describe("runPostToolHooks", () => {
  let context: McpToolContext;
  const response: McpToolResponse = {
    content: [{ type: "text", text: "{}" }],
  };

  beforeEach(() => {
    context = createMockContext();
  });

  it("runs all hooks sequentially", async () => {
    const order: number[] = [];
    const hook1: PostToolHook = vi.fn(async () => { order.push(1); });
    const hook2: PostToolHook = vi.fn(async () => { order.push(2); });

    await runPostToolHooks([hook1, hook2], response, context);

    expect(hook1).toHaveBeenCalledWith(response, context);
    expect(hook2).toHaveBeenCalledWith(response, context);
    expect(order).toEqual([1, 2]);
  });

  it("continues running hooks when one throws", async () => {
    const hook1: PostToolHook = vi.fn(async () => { throw new Error("hook1 failed"); });
    const hook2: PostToolHook = vi.fn(async () => {});

    await runPostToolHooks([hook1, hook2], response, context);

    expect(hook1).toHaveBeenCalled();
    expect(hook2).toHaveBeenCalled();
  });

  it("handles empty hooks array", async () => {
    await expect(runPostToolHooks([], response, context)).resolves.toBeUndefined();
  });
});
