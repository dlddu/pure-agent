import type { LinearClient } from "@linear/sdk";
import type { IoLayer } from "../io.js";

export type Priority = "urgent" | "high" | "medium" | "low" | "none";

/** Narrow subset of LinearClient methods used by LinearService. */
export type LinearClientLike = Pick<
  LinearClient,
  "createIssue" | "issue" | "createComment"
>;

export interface CreateIssueInput {
  title: string;
  reason: string;
  priority?: Priority;
}

export interface CreateIssueResult {
  issueId: string;
  issueUrl: string;
  issueIdentifier: string;
}

export interface IssueResult {
  id: string;
  identifier: string;
  title: string;
  description?: string;
  state: { name: string; type: string };
  priority: number;
  priorityLabel: string;
  labels: Array<{ id: string; name: string; color: string }>;
  assignee?: { id: string; name: string; email: string };
  url: string;
  createdAt: string;
  updatedAt: string;
  dueDate?: string;
  estimate?: number;
}

export interface CommentResult {
  id: string;
  body: string;
  user?: { id: string; name: string; email: string };
  createdAt: string;
  updatedAt: string;
  url: string;
}

export interface LinearServiceOptions {
  client: LinearClientLike;
  teamId: string;
  defaultProjectId?: string;
  defaultLabelId?: string;
}

export interface ILinearService {
  createFeatureRequest(input: CreateIssueInput): Promise<CreateIssueResult>;
  getIssue(issueId: string): Promise<IssueResult>;
  createComment(issueId: string, body: string): Promise<{ commentId: string }>;
  getIssueComments(issueId: string): Promise<CommentResult[]>;
}

export interface SessionServiceOptions {
  workDir: string;
  io: IoLayer;
}

export type SessionSource = "planner" | "agent";

export interface SessionInfo {
  sessionId: string;
  source: SessionSource;
}

export interface ISessionService {
  readSessionId(): Promise<SessionInfo | undefined>;
}

export interface GatekeeperServiceOptions {
  gatekeeperUrl: string;
  apiKey: string;
  userId: string;
  pollIntervalMs?: number;
  timeoutMs?: number;
  requesterName?: string;
  io: IoLayer;
  logger?: import("../logger.js").Logger;
}

export interface ApprovalResult {
  status: "APPROVED" | "REJECTED" | "EXPIRED" | "TIMEOUT";
  requestId?: string;
}

export interface IGatekeeperService {
  requestApproval(
    externalId: string,
    context: string,
  ): Promise<ApprovalResult>;
}

export interface ExchangeRatesServiceOptions {
  bucket?: string;
  region?: string;
  roleArn?: string;
}

export interface IExchangeRatesService {
  /** Returns all S3 object keys under gold/exchange_rates/date=YYYY-MM-DD/ for each day in [startDate, endDate]. */
  listByDateRange(startDate: string, endDate: string): Promise<string[]>;
  /** Downloads a single S3 object as bytes. */
  getObject(key: string): Promise<Uint8Array>;
}
