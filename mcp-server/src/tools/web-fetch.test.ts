// TODO: Activate when DLD-778 is implemented
// All tests in this file are skipped pending web-fetch.ts implementation.
// Remove describe.skip to enable after web_fetch tool is created.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { parseResponseText, createMockContext, createMockExtra } from "../test-utils.js";
import type { McpToolContext } from "./types.js";

// NOTE: web-fetch.ts does not exist yet. This import will resolve once DLD-778 is implemented.
// import { webFetchTool } from "./web-fetch.js";

describe.skip("webFetchTool — DLD-778 (pending implementation)", () => {
  // Placeholder import — replace with real import when web-fetch.ts exists:
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let webFetchTool: any;
  let context: McpToolContext;
  let mockFetch: ReturnType<typeof vi.fn>;
  let mockRequestApproval: ReturnType<typeof vi.fn>;
  let mockReadSessionId: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    // When DLD-778 is implemented, replace the dynamic import below with a static import at the top of the file:
    // import { webFetchTool } from "./web-fetch.js";
    const mod = await import("./web-fetch.js");
    webFetchTool = mod.webFetchTool;

    context = createMockContext();

    // context.fetch is not yet part of McpToolContext — cast to any to attach the mock.
    // When web-fetch.ts is implemented, McpToolContext should gain a `fetch` property.
    mockFetch = vi.fn();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (context as any).fetch = mockFetch;

    mockRequestApproval = context.services.gatekeeper.requestApproval as ReturnType<typeof vi.fn>;
    mockReadSessionId = context.services.session.readSessionId as ReturnType<typeof vi.fn>;
  });

  // ---------------------------------------------------------------------------
  // Input validation
  // ---------------------------------------------------------------------------

  describe("input validation", () => {
    it("rejects when url is missing", async () => {
      const result = await webFetchTool.handler({}, context, createMockExtra());
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when url is empty string", async () => {
      const result = await webFetchTool.handler({ url: "" }, context, createMockExtra());
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when url is not a valid URL format", async () => {
      const result = await webFetchTool.handler(
        { url: "not-a-valid-url" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when method is not an allowed value (e.g. PATCH)", async () => {
      const result = await webFetchTool.handler(
        { url: "https://example.com/api", method: "PATCH" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("rejects when args is null", async () => {
      const result = await webFetchTool.handler(null, context, createMockExtra());
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // session_id handling
  // ---------------------------------------------------------------------------

  describe("session_id handling", () => {
    it('returns "Session ID not found" error when sessionService.readSessionId() returns undefined', async () => {
      mockReadSessionId.mockResolvedValue(undefined);

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("Session ID not found");
    });

    it("proceeds normally when sessionService.readSessionId() returns a valid session id", async () => {
      mockReadSessionId.mockResolvedValue("session-abc-123");
      mockRequestApproval.mockResolvedValue({ status: "APPROVED", requestId: "req-mock-1" });
      mockFetch.mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("application/json") },
        text: vi.fn().mockResolvedValue('{"ok":true}'),
      });

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );

      // Should not fail with session error — may succeed or fail for other reasons
      const parsed = parseResponseText(result);
      expect(parsed.error).not.toContain("Session ID not found");
    });
  });

  // ---------------------------------------------------------------------------
  // externalId construction
  // ---------------------------------------------------------------------------

  describe("externalId construction", () => {
    it("passes externalId in '{session_id}:{requestId}' format to requestApproval", async () => {
      mockReadSessionId.mockResolvedValue("session-xyz");
      mockRequestApproval.mockResolvedValue({ status: "APPROVED", requestId: "req-mock-1" });
      mockFetch.mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("text/plain") },
        text: vi.fn().mockResolvedValue("hello"),
      });

      const extra = createMockExtra({ requestId: "req-42" });
      await webFetchTool.handler({ url: "https://example.com" }, context, extra);

      expect(mockRequestApproval).toHaveBeenCalledWith(
        "session-xyz:req-42",
        expect.any(String),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Approval flow
  // ---------------------------------------------------------------------------

  describe("approval flow", () => {
    beforeEach(() => {
      mockReadSessionId.mockResolvedValue("session-abc");
    });

    it("performs fetch when requestApproval returns APPROVED", async () => {
      mockRequestApproval.mockResolvedValue({ status: "APPROVED", requestId: "req-mock-1" });
      mockFetch.mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("text/html") },
        text: vi.fn().mockResolvedValue("<html>ok</html>"),
      });

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBeFalsy();
      expect(parsed.success).toBe(true);
      expect(mockFetch).toHaveBeenCalledTimes(1);
    });

    it("returns error and does not fetch when requestApproval returns REJECTED", async () => {
      mockRequestApproval.mockResolvedValue({ status: "REJECTED", requestId: "req-mock-1" });

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(mockFetch).not.toHaveBeenCalled();
    });

    it("returns error when requestApproval returns EXPIRED", async () => {
      mockRequestApproval.mockResolvedValue({ status: "EXPIRED" });

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });

    it("returns error when requestApproval returns TIMEOUT", async () => {
      mockRequestApproval.mockResolvedValue({ status: "TIMEOUT" });

      const result = await webFetchTool.handler(
        { url: "https://example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // HTTP fetch execution
  // ---------------------------------------------------------------------------

  describe("HTTP fetch execution", () => {
    beforeEach(() => {
      mockReadSessionId.mockResolvedValue("session-abc");
      mockRequestApproval.mockResolvedValue({ status: "APPROVED", requestId: "req-mock-1" });
    });

    it("returns { status, headers, body } on successful GET request", async () => {
      mockFetch.mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("application/json") },
        text: vi.fn().mockResolvedValue('{"data":"value"}'),
      });

      const result = await webFetchTool.handler(
        { url: "https://api.example.com/data", method: "GET" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBeFalsy();
      expect(parsed.success).toBe(true);
      expect(parsed.status).toBe(200);
      expect(parsed.body).toContain("value");
      expect(parsed.headers).toBeDefined();
    });

    it("forwards method, headers, and body correctly for POST request", async () => {
      mockFetch.mockResolvedValue({
        status: 201,
        headers: { get: vi.fn().mockReturnValue("application/json") },
        text: vi.fn().mockResolvedValue('{"created":true}'),
      });

      await webFetchTool.handler(
        {
          url: "https://api.example.com/items",
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: '{"name":"test"}',
        },
        context,
        createMockExtra(),
      );

      expect(mockFetch).toHaveBeenCalledWith(
        "https://api.example.com/items",
        expect.objectContaining({
          method: "POST",
          headers: expect.objectContaining({ "Content-Type": "application/json" }),
          body: '{"name":"test"}',
        }),
      );
    });

    it("returns error when fetch throws a network error", async () => {
      mockFetch.mockRejectedValue(new Error("Network error: connection refused"));

      const result = await webFetchTool.handler(
        { url: "https://unreachable.example.com" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBe(true);
      expect(parsed.success).toBe(false);
      expect(parsed.error).toContain("Network error");
    });

    it("truncates response body when it exceeds the maximum allowed size", async () => {
      const largeBody = "x".repeat(200_000);
      mockFetch.mockResolvedValue({
        status: 200,
        headers: { get: vi.fn().mockReturnValue("text/plain") },
        text: vi.fn().mockResolvedValue(largeBody),
      });

      const result = await webFetchTool.handler(
        { url: "https://example.com/large" },
        context,
        createMockExtra(),
      );
      const parsed = parseResponseText(result);
      expect(result.isError).toBeFalsy();
      expect(parsed.success).toBe(true);
      // Body must be shorter than the original large body — truncation applied
      expect(parsed.body.length).toBeLessThan(largeBody.length);
    });
  });
});
