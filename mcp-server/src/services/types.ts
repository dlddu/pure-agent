import type { LinearClient } from "@linear/sdk";

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
  readFile: (path: string, encoding: BufferEncoding) => Promise<string>;
}

export interface ISessionService {
  readSessionId(): Promise<string | undefined>;
}
