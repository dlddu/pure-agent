import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { createApp, getCalls, resetCalls, selectEnvironmentFromPrompt } from "./index.js";
import type { RecordedCall } from "./index.js";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeApp() {
  return createApp();
}

function mutationBody(operationName: string, extraFields?: Record<string, unknown>) {
  return {
    query: `mutation ${operationName} { placeholder }`,
    operationName,
    ...extraFields,
  };
}

function queryBody(operationName: string, extraFields?: Record<string, unknown>) {
  return {
    query: `query ${operationName} { placeholder }`,
    operationName,
    ...extraFields,
  };
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

  // ── POST /v1/messages — Anthropic API mock (planner) ──────────────────────

  describe("POST /v1/messages", () => {
    function anthropicBody(prompt: string) {
      return {
        model: "claude-haiku-4-5-20251001",
        max_tokens: 100,
        system: "You are a routing assistant.",
        messages: [{ role: "user", content: prompt }],
      };
    }

    it("returns environment_id=default for general coding prompt", async () => {
      const res = await request(app)
        .post("/v1/messages")
        .send(anthropicBody("Review this Python code and fix bugs"))
        .set("Content-Type", "application/json");

      expect(res.status).toBe(200);
      const text = res.body.content[0].text;
      expect(JSON.parse(text).environment_id).toBe("default");
    });

    it("returns environment_id=python-analysis for data analysis prompt", async () => {
      const res = await request(app)
        .post("/v1/messages")
        .send(anthropicBody("pandas 데이터 분석하고 matplotlib으로 시각화해줘"))
        .set("Content-Type", "application/json");

      expect(res.status).toBe(200);
      const text = res.body.content[0].text;
      expect(JSON.parse(text).environment_id).toBe("python-analysis");
    });

    it("returns environment_id=infra for infrastructure prompt", async () => {
      const res = await request(app)
        .post("/v1/messages")
        .send(anthropicBody("kubectl로 Kubernetes 클러스터에 deploy 해줘"))
        .set("Content-Type", "application/json");

      expect(res.status).toBe(200);
      const text = res.body.content[0].text;
      expect(JSON.parse(text).environment_id).toBe("infra");
    });

    it("records call as type=llm with operationName=selectEnvironment", async () => {
      await request(app)
        .post("/v1/messages")
        .send(anthropicBody("some task"))
        .set("Content-Type", "application/json");

      const recorded = getCalls();
      expect(recorded).toHaveLength(1);
      expect(recorded[0].type).toBe("llm");
      expect(recorded[0].operationName).toBe("selectEnvironment");
    });

    it("stores the full request body in the recorded call", async () => {
      const body = anthropicBody("deploy to AWS");
      await request(app)
        .post("/v1/messages")
        .send(body)
        .set("Content-Type", "application/json");

      const recorded = getCalls();
      const storedBody = recorded[0].body as Record<string, unknown>;
      expect(storedBody["model"]).toBe("claude-haiku-4-5-20251001");
    });

    it("returns proper Anthropic API response structure", async () => {
      const res = await request(app)
        .post("/v1/messages")
        .send(anthropicBody("general task"))
        .set("Content-Type", "application/json");

      expect(res.body.id).toBe("msg_mock_001");
      expect(res.body.type).toBe("message");
      expect(res.body.role).toBe("assistant");
      expect(res.body.stop_reason).toBe("end_turn");
      expect(res.body.content).toHaveLength(1);
      expect(res.body.content[0].type).toBe("text");
    });
  });

  // ── selectEnvironmentFromPrompt (unit) ───────────────────────────────────

  describe("selectEnvironmentFromPrompt", () => {
    it("returns default for general coding prompts", () => {
      expect(selectEnvironmentFromPrompt("fix bugs in my code")).toBe("default");
    });

    it("returns python-analysis for data analysis prompts", () => {
      expect(selectEnvironmentFromPrompt("pandas data analysis")).toBe("python-analysis");
    });

    it("returns python-analysis for Korean data analysis prompts", () => {
      expect(selectEnvironmentFromPrompt("데이터 분석 해줘")).toBe("python-analysis");
    });

    it("returns infra for kubernetes prompts", () => {
      expect(selectEnvironmentFromPrompt("deploy with kubernetes")).toBe("infra");
    });

    it("returns infra for Korean infrastructure prompts", () => {
      expect(selectEnvironmentFromPrompt("인프라 관리해줘")).toBe("infra");
    });

    it("returns default for empty prompt", () => {
      expect(selectEnvironmentFromPrompt("")).toBe("default");
    });
  });

  // ── POST /graphql — mutations ─────────────────────────────────────────────

  describe("POST /graphql — mutations", () => {
    it("records a mutation call in memory", async () => {
      // Arrange
      const body = mutationBody("createComment");

      // Act
      await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      expect(recorded).toHaveLength(1);
      expect(recorded[0].type).toBe("mutation");
      expect(recorded[0].operationName).toBe("createComment");
    });

    it("returns canned success response for createComment mutation", async () => {
      // Arrange
      const body = mutationBody("createComment");

      // Act
      const res = await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.data.commentCreate.success).toBe(true);
      expect(res.body.data.commentCreate.comment.id).toBe("mock-comment-id");
    });

    it("returns generic success for unknown mutation", async () => {
      // Arrange
      const body = mutationBody("someUnknownMutation");

      // Act
      const res = await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.data.mutationResult.success).toBe(true);
    });

    it("stores the full request body in the recorded call", async () => {
      // Arrange
      const body = mutationBody("createComment", { variables: { issueId: "issue-1", body: "hello" } });

      // Act
      await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      const storedBody = recorded[0].body as Record<string, unknown>;
      expect(storedBody["variables"]).toEqual({ issueId: "issue-1", body: "hello" });
    });

    it("records timestamp for each mutation call", async () => {
      // Act
      await request(app)
        .post("/graphql")
        .send(mutationBody("createComment"))
        .set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      expect(recorded[0].timestamp).toBeTruthy();
      expect(new Date(recorded[0].timestamp).toISOString()).toBe(recorded[0].timestamp);
    });

    it("records multiple mutation calls independently", async () => {
      // Act
      await request(app).post("/graphql").send(mutationBody("createComment")).set("Content-Type", "application/json");
      await request(app).post("/graphql").send(mutationBody("updateIssue")).set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      expect(recorded).toHaveLength(2);
      expect(recorded[0].operationName).toBe("createComment");
      expect(recorded[1].operationName).toBe("updateIssue");
    });
  });

  // ── POST /graphql — queries ───────────────────────────────────────────────

  describe("POST /graphql — queries", () => {
    it("records a query call in memory", async () => {
      // Arrange
      const body = queryBody("GetIssue");

      // Act
      await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      const recorded = getCalls();
      expect(recorded).toHaveLength(1);
      expect(recorded[0].type).toBe("query");
      expect(recorded[0].operationName).toBe("GetIssue");
    });

    it("returns fixture data for issue query", async () => {
      // Arrange
      const body = queryBody("GetIssue");

      // Act
      const res = await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      const issue = res.body.data.issue;
      expect(issue.id).toBe("mock-issue-id");
      expect(issue.identifier).toBe("MOCK-1");
      expect(issue.title).toBe("Mock Issue Title");
    });

    it("returns generic empty data for unknown query", async () => {
      // Arrange
      const body = queryBody("SomeUnknownQuery");

      // Act
      const res = await request(app).post("/graphql").send(body).set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(200);
      expect(res.body.data).toBeDefined();
    });

    it("returns 400 when query field is missing", async () => {
      // Act
      const res = await request(app)
        .post("/graphql")
        .send({ operationName: "Oops" })
        .set("Content-Type", "application/json");

      // Assert
      expect(res.status).toBe(400);
      expect(res.body.errors[0].message).toContain("Missing query field");
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

    it("returns recorded mutation calls", async () => {
      // Arrange
      await request(app).post("/graphql").send(mutationBody("createComment")).set("Content-Type", "application/json");

      // Act
      const res = await request(app).get("/assertions");

      // Assert
      expect(res.status).toBe(200);
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(1);
      expect(calls[0].type).toBe("mutation");
      expect(calls[0].operationName).toBe("createComment");
    });

    it("returns recorded query calls alongside mutations", async () => {
      // Arrange
      await request(app).post("/graphql").send(queryBody("GetIssue")).set("Content-Type", "application/json");
      await request(app).post("/graphql").send(mutationBody("createComment")).set("Content-Type", "application/json");

      // Act
      const res = await request(app).get("/assertions");

      // Assert
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(2);
      expect(calls[0].type).toBe("query");
      expect(calls[1].type).toBe("mutation");
    });
  });

  // ── POST /assertions/reset ────────────────────────────────────────────────

  describe("POST /assertions/reset", () => {
    it("clears all recorded calls and returns ok", async () => {
      // Arrange — add some calls first
      await request(app).post("/graphql").send(mutationBody("createComment")).set("Content-Type", "application/json");
      await request(app).post("/graphql").send(mutationBody("updateIssue")).set("Content-Type", "application/json");

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

    it("allows new calls to be recorded after reset", async () => {
      // Arrange
      await request(app).post("/graphql").send(mutationBody("createComment")).set("Content-Type", "application/json");
      await request(app).post("/assertions/reset");

      // Act
      await request(app).post("/graphql").send(mutationBody("updateIssue")).set("Content-Type", "application/json");

      // Assert
      const res = await request(app).get("/assertions");
      const calls: RecordedCall[] = res.body.calls;
      expect(calls).toHaveLength(1);
      expect(calls[0].operationName).toBe("updateIssue");
    });
  });
});
