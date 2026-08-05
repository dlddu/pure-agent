import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { createApp, getCalls, resetCalls, getMockEnvironmentId } from "./index.js";
import type { RecordedCall } from "./index.js";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeApp() {
  return createApp();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("mock-api", () => {
  let app: ReturnType<typeof makeApp>;

  beforeEach(() => {
    resetCalls();
    app = makeApp();
  });

  // ── GET /health ──────────────────────────────────────────────────────────────

  describe("GET /health", () => {
    it("returns 200 with status ok", async () => {
      // Act
      const res = await request(app).get("/health");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ status: "ok" });
    });
  });

  describe("POST /api/transcripts/upload-url/:sessionId", () => {
    it("returns a PUT URL into the LocalStack bucket for a main transcript", async () => {
      // Act
      const res = await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "abc123.jsonl" });

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.method).toBe("PUT");
      expect(res.body.session_id).toBe("abc123");
      expect(res.body.key).toBe("abc123/abc123.jsonl");
      expect(res.body.url).toContain("/abc123/abc123.jsonl");
      expect(res.body.url).toContain("pure-agent-e2e-transcripts");
    });

    it("keeps the subagents/ prefix in the key for subagent transcripts", async () => {
      // Act
      const res = await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "subagents/sub1.jsonl" });

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.key).toBe("abc123/subagents/sub1.jsonl");
      expect(res.body.url).toContain("/abc123/subagents/sub1.jsonl");
    });

    it("honors LOCALSTACK_S3_ENDPOINT and S3_BUCKET env overrides", async () => {
      // Arrange
      const prevEndpoint = process.env["LOCALSTACK_S3_ENDPOINT"];
      const prevBucket = process.env["S3_BUCKET"];
      process.env["LOCALSTACK_S3_ENDPOINT"] = "http://ls.test:4566";
      process.env["S3_BUCKET"] = "custom-bucket";

      try {
        // Act
        const res = await request(app)
          .post("/api/transcripts/upload-url/sess")
          .query({ file_name: "sess.jsonl" });

        // Assert
        expect(res.status).toBe(200);
        expect(res.body.url).toBe("http://ls.test:4566/custom-bucket/sess/sess.jsonl");
      } finally {
        if (prevEndpoint === undefined) delete process.env["LOCALSTACK_S3_ENDPOINT"];
        else process.env["LOCALSTACK_S3_ENDPOINT"] = prevEndpoint;
        if (prevBucket === undefined) delete process.env["S3_BUCKET"];
        else process.env["S3_BUCKET"] = prevBucket;
      }
    });

    it("records the upload-url request in assertions", async () => {
      // Act
      await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "abc123.jsonl" });

      // Assert
      const recorded = getCalls();
      expect(recorded).toHaveLength(1);
      expect(recorded[0].operationName).toBe("transcript_upload_url");
    });

    it("returns 400 when file_name is missing", async () => {
      // Act
      const res = await request(app).post("/api/transcripts/upload-url/abc123");

      // Assert
      expect(res.status).toBe(400);
      expect(res.body.error).toContain("file_name");
    });

    it("returns 400 for a file_name outside the accepted format", async () => {
      // Act
      const res = await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "../escape.txt" });

      // Assert
      expect(res.status).toBe(400);
    });
  });

  // ── GET /assertions ───────────────────────────────────────────────────────

  describe("GET /assertions", () => {
    it("returns empty calls array when no requests have been made", async () => {
      // Act
      const res = await request(app).get("/assertions");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.calls).toEqual([]);
    });

    it("returns recorded LLM calls", async () => {
      // Arrange
      await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");

      // Act
      const res = await request(app).get("/assertions");

      // Assert
      expect(res.status).toBe(200);
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(1);
      expect(calls[0].type).toBe("query");
      expect(calls[0].operationName).toBe("llm_messages");
    });

    it("returns recorded transcript upload-url calls alongside LLM calls", async () => {
      // Arrange
      await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");
      await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "abc123.jsonl" });

      // Act
      const res = await request(app).get("/assertions");

      // Assert
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(2);
      expect(calls[0].type).toBe("query");
      expect(calls[1].type).toBe("mutation");
      expect(calls[1].operationName).toBe("transcript_upload_url");
    });
  });

  // ── POST /v1/messages — Mock Anthropic Messages API ──────────────────────

  describe("POST /v1/messages", () => {
    it("returns mock LLM response with default environment_id", async () => {
      // Act
      const res = await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.id).toBe("msg_mock");
      expect(res.body.type).toBe("message");
      const text = JSON.parse(res.body.content[0].text);
      expect(text.environment_id).toBe("default");
    });

    it("records LLM call in assertions", async () => {
      // Act
      await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      expect(recorded).toHaveLength(1);
      expect(recorded[0].operationName).toBe("llm_messages");
    });

    it("returns configured environment_id after /v1/messages/configure", async () => {
      // Arrange
      await request(app)
        .post("/v1/messages/configure")
        .send({ environment_id: "python-analysis" })
        .set("Content-Type", "application/json");

      // Act
      const res = await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "analyze data" }] })
        .set("Content-Type", "application/json");

      // Assert
      const text = JSON.parse(res.body.content[0].text);
      expect(text.environment_id).toBe("python-analysis");
    });
  });

  // ── POST /v1/messages/configure ─────────────────────────────────────────

  describe("POST /v1/messages/configure", () => {
    it("sets the mock environment_id", async () => {
      // Act
      const res = await request(app)
        .post("/v1/messages/configure")
        .send({ environment_id: "infra" })
        .set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.ok).toBe(true);
      expect(res.body.environment_id).toBe("infra");
      expect(getMockEnvironmentId()).toBe("infra");
    });

    it("defaults to 'default' when environment_id is empty", async () => {
      // Act
      const res = await request(app)
        .post("/v1/messages/configure")
        .send({})
        .set("Content-Type", "application/json");

      // Assert
      expect(res.body.environment_id).toBe("default");
    });
  });

  // ── POST /assertions/reset ────────────────────────────────────────────────

  describe("POST /assertions/reset", () => {
    it("clears all recorded calls and returns ok", async () => {
      // Arrange — add some calls first
      await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");
      await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "abc123.jsonl" });

      // Act
      const resetRes = await request(app).post("/assertions/reset");

      // Assert
      expect(resetRes.status).toBe(200);
      expect(resetRes.body).toEqual({ ok: true });

      const assertRes = await request(app).get("/assertions");
      expect(assertRes.body.calls).toEqual([]);
    });

    it("is idempotent when called on an already-empty store", async () => {
      // Act
      const res = await request(app).post("/assertions/reset");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ ok: true });
      expect(getCalls()).toEqual([]);
    });

    it("resets mock environment_id to default", async () => {
      // Arrange
      await request(app)
        .post("/v1/messages/configure")
        .send({ environment_id: "infra" })
        .set("Content-Type", "application/json");

      // Act
      await request(app).post("/assertions/reset");

      // Assert
      expect(getMockEnvironmentId()).toBe("default");
    });

    it("allows new calls to be recorded after reset", async () => {
      // Arrange
      await request(app)
        .post("/v1/messages")
        .send({ model: "claude-haiku-4-5-20251001", messages: [{ role: "user", content: "test" }] })
        .set("Content-Type", "application/json");
      await request(app).post("/assertions/reset");

      // Act
      await request(app)
        .post("/api/transcripts/upload-url/abc123")
        .query({ file_name: "abc123.jsonl" });

      // Assert
      const res = await request(app).get("/assertions");
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(1);
      expect(calls[0].operationName).toBe("transcript_upload_url");
    });
  });
});
