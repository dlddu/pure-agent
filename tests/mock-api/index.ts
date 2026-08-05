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

// ── Transcript upload-url mock ──────────────────────────────────────────────
// Stands in for the transcript viewer's upload-url endpoint. It hands back a
// direct PUT URL to the LocalStack S3 service so the gate's two-step upload
// lands real objects in the test bucket. LocalStack accepts unsigned PUTs, so
// no presigning is required.

// Mirrors the file names the real viewer accepts.
const TRANSCRIPT_FILE_NAME_RE = /^(subagents\/)?[A-Za-z0-9._-]+\.jsonl$/;

function localstackS3Endpoint(): string {
  return (
    process.env["LOCALSTACK_S3_ENDPOINT"] ??
    "http://localstack.pure-agent.svc.cluster.local:4566"
  );
}

function transcriptBucket(): string {
  return process.env["S3_BUCKET"] ?? "pure-agent-e2e-transcripts";
}

// ── App factory ───────────────────────────────────────────────────────────────

export function createApp(): express.Application {
  const app = express();
  app.use(express.json());

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

  // POST /api/transcripts/upload-url/:sessionId — transcript viewer upload-url mock
  app.post("/api/transcripts/upload-url/:sessionId", (req: Request, res: Response) => {
    const { sessionId } = req.params as { sessionId: string };
    const fileName = req.query["file_name"];

    if (typeof fileName !== "string" || !TRANSCRIPT_FILE_NAME_RE.test(fileName)) {
      res.status(400).json({ error: "Invalid or missing file_name" });
      return;
    }

    const key = `${sessionId}/${fileName}`;
    const url = `${localstackS3Endpoint()}/${transcriptBucket()}/${key}`;

    calls.push({
      type: "mutation",
      operationName: "transcript_upload_url",
      body: { sessionId, fileName },
      timestamp: new Date().toISOString(),
    });

    res.status(200).json({
      url,
      method: "PUT",
      key,
      session_id: sessionId,
      expires_in: 3600,
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
