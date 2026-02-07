import { LinearClient } from "@linear/sdk";

const PRIORITY_MAP = {
  urgent: 1,
  high: 2,
  medium: 3,
  low: 4,
  none: 0,
} as const;

export type Priority = keyof typeof PRIORITY_MAP;

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

export interface LinearServiceOptions {
  apiKey: string;
  teamId: string;
  defaultProjectId?: string;
  defaultLabelId?: string;
}

export class LinearService {
  private client: LinearClient;
  private teamId: string;
  private defaultProjectId?: string;
  private defaultLabelId?: string;

  constructor(options: LinearServiceOptions) {
    this.client = new LinearClient({ apiKey: options.apiKey });
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
}
