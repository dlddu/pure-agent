import express from "express";
import type { Request, Response } from "express";

// ── Types ─────────────────────────────────────────────────────────────────────

export interface RecordedCall {
  type: "mutation" | "query";
  operationName: string | null;
  body: unknown;
  timestamp: string;
}

// ── In-memory store ───────────────────────────────────────────────────────────

const calls: RecordedCall[] = [];
let mockEnvironmentId = "default";

export function getCalls(): RecordedCall[] {
  return calls;
}

export function resetCalls(): void {
  calls.length = 0;
  mockEnvironmentId = "default";
}

export function getMockEnvironmentId(): string {
  return mockEnvironmentId;
}

export function setMockEnvironmentId(id: string): void {
  mockEnvironmentId = id;
}

// ── GraphQL helpers ───────────────────────────────────────────────────────────

function isMutation(query: string): boolean {
  return /^\s*mutation\b/i.test(query);
}

function buildMutationResponse(operationName: string | null, query: string): unknown {
  // Match comment creation by operationName OR by query body content.
  // The @linear/sdk may send different operationName formats.
  const isCommentCreate =
    operationName === "createComment" ||
    operationName === "CreateComment" ||
    operationName === "CommentCreate" ||
    /commentCreate\s*\(/.test(query);

  if (isCommentCreate) {
    return {
      data: {
        commentCreate: {
          lastSyncId: 1000,
          success: true,
          comment: {
            id: "mock-comment-id",
            body: "mock comment body",
            url: "https://linear.app/mock/comment/mock-comment-id",
          },
        },
      },
    };
  }

  // Generic mutation success response
  return {
    data: {
      mutationResult: {
        lastSyncId: 1000,
        success: true,
      },
    },
  };
}

function buildQueryResponse(operationName: string | null): unknown {
  if (operationName === "issue" || operationName === "Issue" || operationName === "GetIssue") {
    return {
      data: {
        issue: {
          id: "mock-issue-id",
          identifier: "MOCK-1",
          title: "Mock Issue Title",
          description: "Mock issue description for e2e testing",
          state: { name: "In Progress", type: "started" },
          priority: 2,
          priorityLabel: "High",
          labels: { nodes: [] },
          assignee: null,
          url: "https://linear.app/mock/issue/MOCK-1",
          createdAt: "2025-01-01T00:00:00.000Z",
          updatedAt: "2025-01-01T00:00:00.000Z",
        },
      },
    };
  }

  // Generic query response
  return {
    data: {},
  };
}

// ── App factory ───────────────────────────────────────────────────────────────

export function createApp(): express.Application {
  const app = express();
  app.use(express.json());

  // POST /graphql — Linear GraphQL mock
  app.post("/graphql", (req: Request, res: Response) => {
    const { query, operationName } = req.body as {
      query?: string;
      operationName?: string | null;
    };

    if (!query) {
      res.status(400).json({ errors: [{ message: "Missing query field" }] });
      return;
    }

    const resolvedOperationName = operationName ?? null;
    const type: "mutation" | "query" = isMutation(query) ? "mutation" : "query";

    calls.push({
      type,
      operationName: resolvedOperationName,
      body: req.body,
      timestamp: new Date().toISOString(),
    });

    const response =
      type === "mutation"
        ? buildMutationResponse(resolvedOperationName, query)
        : buildQueryResponse(resolvedOperationName);

    res.status(200).json(response);
  });

  // ── Mock Anthropic Messages API (planner용) ───────────────────────────

  // POST /v1/messages/configure — mock LLM 환경 설정
  app.post("/v1/messages/configure", (req: Request, res: Response) => {
    const { environment_id } = req.body as { environment_id?: string };
    mockEnvironmentId = environment_id || "default";
    res.status(200).json({ ok: true, environment_id: mockEnvironmentId });
  });

  // POST /v1/messages — Anthropic Messages API mock
  app.post("/v1/messages", (req: Request, res: Response) => {
    calls.push({
      type: "query",
      operationName: "llm_messages",
      body: req.body,
      timestamp: new Date().toISOString(),
    });
    res.status(200).json({
      id: "msg_mock",
      type: "message",
      role: "assistant",
      content: [
        { type: "text", text: JSON.stringify({ environment_id: mockEnvironmentId }) },
      ],
      model: "claude-haiku-4-5-20251001",
      stop_reason: "end_turn",
      usage: { input_tokens: 10, output_tokens: 10 },
    });
  });

  // GET /assertions — return recorded calls
  app.get("/assertions", (_req: Request, res: Response) => {
    res.status(200).json({ calls });
  });

  // POST /assertions/reset — clear recorded calls
  app.post("/assertions/reset", (_req: Request, res: Response) => {
    resetCalls();
    res.status(200).json({ ok: true });
  });

  // GET /health
  app.get("/health", (_req: Request, res: Response) => {
    res.status(200).json({ status: "ok" });
  });

  return app;
}

// ── Entrypoint ────────────────────────────────────────────────────────────────

const PORT = process.env["PORT"] ? parseInt(process.env["PORT"], 10) : 4000;

const app = createApp();
app.listen(PORT, () => {
  console.log(`mock-api listening on port ${PORT}`);
});
