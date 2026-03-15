import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { GatekeeperService } from "./gatekeeper.js";
import type { ApprovalResult, GatekeeperServiceOptions } from "./types.js";

describe("GatekeeperService", () => {
  let mockFetch: ReturnType<typeof vi.fn>;
  let defaultOptions: GatekeeperServiceOptions;

  beforeEach(() => {
    mockFetch = vi.fn();
    defaultOptions = {
      gatekeeperUrl: "https://gatekeeper.example.com",
      apiKey: "gk_api_test123",
      userId: "user-test123",
      pollIntervalMs: 100,
      timeoutMs: 5000,
      fetch: mockFetch as typeof globalThis.fetch,
    };
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("requestApproval", () => {
    it("returns APPROVED when approval request is approved", async () => {
      // POST /api/requests → 201 { requestId: "req-abc" }
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        // GET /api/requests/req-abc → 200 { status: "APPROVED" }
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "APPROVED" }),
        } as Response);

      const service = new GatekeeperService(defaultOptions);
      const result: ApprovalResult = await service.requestApproval("ext-id-001", "Test approval context");

      expect(result).toEqual({ status: "APPROVED", requestId: "req-abc" });
    });

    it("returns REJECTED when approval request is rejected", async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "REJECTED" }),
        } as Response);

      const service = new GatekeeperService(defaultOptions);
      const result: ApprovalResult = await service.requestApproval("ext-id-001", "Test approval context");

      expect(result).toEqual({ status: "REJECTED", requestId: "req-abc" });
    });

    it("returns EXPIRED when approval request expires", async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "EXPIRED" }),
        } as Response);

      const service = new GatekeeperService(defaultOptions);
      const result: ApprovalResult = await service.requestApproval("ext-id-001", "Test approval context");

      expect(result).toEqual({ status: "EXPIRED", requestId: "req-abc" });
    });

    it("makes new HTTP requests for each call even with the same externalId", async () => {
      const makeResponses = () => [
        {
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response,
        {
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "APPROVED" }),
        } as Response,
      ];

      mockFetch
        .mockResolvedValueOnce(makeResponses()[0])
        .mockResolvedValueOnce(makeResponses()[1])
        .mockResolvedValueOnce(makeResponses()[0])
        .mockResolvedValueOnce(makeResponses()[1]);

      const service = new GatekeeperService(defaultOptions);
      await service.requestApproval("same-ext-id", "Same context");
      await service.requestApproval("same-ext-id", "Same context");

      // POST가 두 번 호출되었는지 확인 (캐시 없이 매번 새 요청)
      expect(mockFetch).toHaveBeenCalledTimes(4); // 2 POST + 2 GET
      const postCalls = mockFetch.mock.calls.filter(
        ([_url, init]) => (init as RequestInit)?.method === "POST",
      );
      expect(postCalls).toHaveLength(2);
    });

    it("returns APPROVED after polling through PENDING states", async () => {
      mockFetch
        // POST → 201
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        // GET → PENDING (1차)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "PENDING" }),
        } as Response)
        // GET → PENDING (2차)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "PENDING" }),
        } as Response)
        // GET → APPROVED (3차)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "APPROVED" }),
        } as Response);

      const service = new GatekeeperService(defaultOptions);
      const result: ApprovalResult = await service.requestApproval("ext-id-001", "Test approval context");

      expect(result).toEqual({ status: "APPROVED", requestId: "req-abc" });
      // PENDING 동안 폴링 GET 호출 횟수 확인 (POST 1 + GET 3)
      expect(mockFetch).toHaveBeenCalledTimes(4);
    });

    it("returns TIMEOUT when polling exceeds timeout", async () => {
      vi.useFakeTimers();

      const shortTimeoutOptions: GatekeeperServiceOptions = {
        ...defaultOptions,
        timeoutMs: 300,
        pollIntervalMs: 100,
      };

      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        // 이후 모든 GET 폴링은 PENDING 반환
        .mockResolvedValue({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "PENDING" }),
        } as Response);

      const service = new GatekeeperService(shortTimeoutOptions);
      const resultPromise = service.requestApproval("ext-id-001", "Test approval context");

      // 타임아웃 시간만큼 타이머 진행
      await vi.advanceTimersByTimeAsync(400);

      const result: ApprovalResult = await resultPromise;
      expect(result).toEqual({ status: "TIMEOUT" });
    });

    it("polls at the configured interval", async () => {
      vi.useFakeTimers();

      const intervalMs = 500;
      const timedOptions: GatekeeperServiceOptions = {
        ...defaultOptions,
        pollIntervalMs: intervalMs,
        timeoutMs: 10000,
      };

      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          status: 201,
          json: async () => ({ requestId: "req-abc" }),
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "PENDING" }),
        } as Response)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ requestId: "req-abc", status: "APPROVED" }),
        } as Response);

      const service = new GatekeeperService(timedOptions);
      const resultPromise = service.requestApproval("ext-id-001", "Test approval context");

      // 첫 폴링 직전 — GET은 아직 1번만 호출
      await vi.advanceTimersByTimeAsync(intervalMs - 1);
      expect(mockFetch).toHaveBeenCalledTimes(2); // POST + 첫 GET

      // 두 번째 폴링 시점
      await vi.advanceTimersByTimeAsync(intervalMs);
      await resultPromise;
      expect(mockFetch).toHaveBeenCalledTimes(3); // POST + GET(PENDING) + GET(APPROVED)
    });

    it("throws when Gatekeeper server connection fails", async () => {
      mockFetch.mockRejectedValueOnce(new TypeError("fetch failed"));

      const service = new GatekeeperService(defaultOptions);
      await expect(service.requestApproval("ext-id-001", "Test approval context")).rejects.toThrow();
    });

    it("throws when POST /api/requests returns 4xx/5xx", async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 422,
        json: async () => ({ error: "Invalid externalId" }),
      } as Response);

      const service = new GatekeeperService(defaultOptions);
      await expect(service.requestApproval("ext-id-001", "Test approval context")).rejects.toThrow();
    });

    it("throws when response parsing fails", async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        status: 201,
        json: async () => {
          throw new SyntaxError("Unexpected token < in JSON");
        },
      } as unknown as Response);

      const service = new GatekeeperService(defaultOptions);
      await expect(service.requestApproval("ext-id-001", "Test approval context")).rejects.toThrow();
    });
  });
});
