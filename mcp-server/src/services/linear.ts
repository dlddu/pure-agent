import type {
  Priority,
  CreateIssueInput,
  CreateIssueResult,
  IssueResult,
  CommentResult,
  LinearServiceOptions,
  LinearClientLike,
  ILinearService,
} from "./types.js";

/**
 * Linear issue priority levels.
 * @see https://developers.linear.app/docs/graphql/working-with-the-graphql-api#creating-issues
 * 0 = No priority, 1 = Urgent, 2 = High, 3 = Medium, 4 = Low
 */
const PRIORITY_MAP: Record<Priority, number> = {
  urgent: 1,
  high: 2,
  medium: 3,
  low: 4,
  none: 0,
};

/** Extract { id, name, email } from a nullable Linear user object. */
function mapUser(
  user: { id: string; name: string; email: string } | undefined | null,
): { id: string; name: string; email: string } | undefined {
  return user ? { id: user.id, name: user.name, email: user.email } : undefined;
}

export class LinearService implements ILinearService {
  private client: LinearClientLike;
  private teamId: string;
  private defaultProjectId?: string;
  private defaultLabelId?: string;

  constructor(options: LinearServiceOptions) {
    this.client = options.client;
    this.teamId = options.teamId;
    this.defaultProjectId = options.defaultProjectId;
    this.defaultLabelId = options.defaultLabelId;
  }

  async createFeatureRequest(input: CreateIssueInput): Promise<CreateIssueResult> {
    const priorityValue = input.priority ? PRIORITY_MAP[input.priority] : PRIORITY_MAP.medium;

    const description = `## Reason\n\n${input.reason}`;

    const issuePayload = await this.client.createIssue({
      teamId: this.teamId,
      title: input.title,
      description,
      priority: priorityValue,
      ...(this.defaultProjectId && { projectId: this.defaultProjectId }),
      ...(this.defaultLabelId && { labelIds: [this.defaultLabelId] }),
    });

    const issue = await issuePayload.issue;

    if (!issue) {
      throw new Error("Failed to create Linear issue");
    }

    return {
      issueId: issue.id,
      issueUrl: issue.url,
      issueIdentifier: issue.identifier,
    };
  }

  async getIssue(issueId: string): Promise<IssueResult> {
    const issue = await this.client.issue(issueId);

    const [state, assignee, labelsConnection] = await Promise.all([
      issue.state,
      issue.assignee,
      issue.labels(),
    ]);

    if (!state) {
      throw new Error("Failed to fetch issue state");
    }

    return {
      id: issue.id,
      identifier: issue.identifier,
      title: issue.title,
      description: issue.description,
      state: { name: state.name, type: state.type },
      priority: issue.priority,
      priorityLabel: issue.priorityLabel,
      labels: labelsConnection.nodes.map((l) => ({
        id: l.id,
        name: l.name,
        color: l.color,
      })),
      assignee: mapUser(assignee),
      url: issue.url,
      createdAt: issue.createdAt.toISOString(),
      updatedAt: issue.updatedAt.toISOString(),
      dueDate: issue.dueDate ?? undefined,
      estimate: issue.estimate ?? undefined,
    };
  }

  async createComment(issueId: string, body: string): Promise<{ commentId: string }> {
    const result = await this.client.createComment({ issueId, body });
    if (!result.success) {
      throw new Error("Failed to create comment on Linear issue");
    }
    const comment = await result.comment;
    if (!comment) {
      throw new Error("Comment was created but could not be retrieved");
    }
    return { commentId: comment.id };
  }

  async getIssueComments(issueId: string): Promise<CommentResult[]> {
    const issue = await this.client.issue(issueId);
    const commentsConnection = await issue.comments();

    const comments = await Promise.all(
      commentsConnection.nodes.map(async (comment) => {
        const user = await comment.user;
        return {
          id: comment.id,
          body: comment.body,
          user: mapUser(user),
          createdAt: comment.createdAt.toISOString(),
          updatedAt: comment.updatedAt.toISOString(),
          url: comment.url,
        };
      }),
    );

    return comments;
  }
}
