import { describe, it, expect, vi, beforeAll } from "vitest";
import supertest from "supertest";
import type { LinearService } from "./services/linear.js";
import { createMcpServer } from "./server.js";
import { createHttpTransport } from "./transport.js";

const { mockWriteFileSync } = vi.hoisted(() => ({
  mockWriteFileSync: vi.fn(),
}));

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    writeFileSync: mockWriteFileSync,
  };
});

describe("createHttpTransport", () => {
  let request: supertest.Agent;

  beforeAll(() => {
    const mockLinearService = {
      createFeatureRequest: vi.fn().mockResolvedValue({
        issueId: "id",
        issueIdentifier: "PA-1",
        issueUrl: "url",
      }),
    } as unknown as LinearService;

    const app = createHttpTransport(
      () => createMcpServer(mockLinearService),
      "/mcp"
    );
    request = supertest(app);
  });

  describe("health endpoint", () => {
    it('GET /health returns 200 with status "healthy"', async () => {
      const res = await request.get("/health").expect(200);

      expect(res.body.status).toBe("healthy");
      expect(res.body.version).toBe("1.0.0");
    });

    it("GET /health returns a valid ISO timestamp", async () => {
      const res = await request.get("/health").expect(200);

      const timestamp = new Date(res.body.timestamp);
      expect(timestamp.toISOString()).toBe(res.body.timestamp);
    });
  });

  describe("ready endpoint", () => {
    it("GET /ready returns 200 with ready: true", async () => {
      const res = await request.get("/ready").expect(200);

      expect(res.body.ready).toBe(true);
    });
  });

  describe("MCP endpoint", () => {
    it("POST /mcp initialize returns 200", async () => {
      const res = await request
        .post("/mcp")
        .set("Content-Type", "application/json")
        .set("Accept", "application/json, text/event-stream")
        .send({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: "2025-03-26",
            capabilities: {},
            clientInfo: { name: "test", version: "1.0.0" },
          },
        });

      expect(res.status).toBe(200);
    });

    it("GET /mcp returns 405 Method Not Allowed", async () => {
      const res = await request.get("/mcp");

      expect(res.status).toBe(405);
      expect(res.body.error.message).toBe("Method not allowed.");
    });

    it("DELETE /mcp returns 405 Method Not Allowed", async () => {
      const res = await request.delete("/mcp");

      expect(res.status).toBe(405);
      expect(res.body.error.message).toBe("Method not allowed.");
    });
  });
});
