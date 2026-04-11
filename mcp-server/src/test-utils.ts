import { vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer, type McpServerDeps } from "./server.js";
import type { ILinearService, ISessionService, IGatekeeperService } from "./services/types.js";
import type { IoLayer } from "./io.js";
import type { McpToolContext, McpToolExtra } from "./tools/types.js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseResponseText(result: Record<string, any>) {
  return JSON.parse(result.content[0].text);
}

export function createMockLinearService(
  overrides?: Partial<Record<keyof ILinearService, ReturnType<typeof vi.fn>>>,
): ILinearService {
  return {
    createFeatureRequest: vi.fn().mockResolvedValue({
      issueId: "issue-1",
      issueIdentifier: "PA-1",
      issueUrl: "https://linear.app/issue/PA-1",
    }),
    getIssue: vi.fn().mockResolvedValue({
      id: "issue-1",
      identifier: "PA-1",
      title: "Test Issue",
      description: "Test description",
      state: { name: "In Progress", type: "started" },
      priority: 2,
      priorityLabel: "High",
      labels: [{ id: "label-1", name: "Bug", color: "#ff0000" }],
      assignee: { id: "user-1", name: "Test User", email: "test@example.com" },
      url: "https://linear.app/issue/PA-1",
      createdAt: "2025-01-01T00:00:00.000Z",
      updatedAt: "2025-01-02T00:00:00.000Z",
    }),
    createComment: vi.fn().mockResolvedValue({ commentId: "comment-1" }),
    getIssueComments: vi.fn().mockResolvedValue([
      {
        id: "comment-1",
        body: "This is a comment",
        user: { id: "user-1", name: "Test User", email: "test@example.com" },
        createdAt: "2025-01-01T00:00:00.000Z",
        updatedAt: "2025-01-01T00:00:00.000Z",
        url: "https://linear.app/issue/PA-1#comment-1",
      },
    ]),
    ...overrides,
  } as ILinearService;
}

export function createMockSessionService(
  overrides?: Partial<Record<keyof ISessionService, ReturnType<typeof vi.fn>>>,
): ISessionService {
  return {
    readSessionId: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  } as ISessionService;
}

export function createMockGatekeeperService(
  overrides?: Partial<Record<keyof IGatekeeperService, ReturnType<typeof vi.fn>>>,
): IGatekeeperService {
  return {
    requestApproval: vi.fn().mockResolvedValue({ status: "APPROVED", requestId: "req-mock-1" }),
    ...overrides,
  } as IGatekeeperService;
}

export function createMockLogger() {
  return {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  };
}

export function createMockFs() {
  return {
    writeFile: vi.fn().mockResolvedValue(undefined),
    readFile: vi.fn().mockResolvedValue(""),
    access: vi.fn().mockRejectedValue(new Error("ENOENT")),
  };
}

export function createMockExec() {
  return {
    execFile: vi.fn().mockResolvedValue({ stdout: "", stderr: "" }),
  };
}

export function createMockIo(): IoLayer {
  return {
    fs: {
      ...createMockFs(),
      stat: vi.fn().mockResolvedValue({ mtimeMs: 0 }),
    },
    exec: createMockExec(),
    fetch: vi.fn() as unknown as typeof globalThis.fetch,
  };
}

export function createMockExtra(overrides?: Partial<McpToolExtra>): McpToolExtra {
  return {
    requestId: "test-req-1",
    signal: new AbortController().signal,
    ...overrides,
  };
}

export function createMockContext(overrides?: {
  linear?: Partial<Record<keyof ILinearService, ReturnType<typeof vi.fn>>>;
  session?: Partial<Record<keyof ISessionService, ReturnType<typeof vi.fn>>>;
  gatekeeper?: Partial<Record<keyof IGatekeeperService, ReturnType<typeof vi.fn>>>;
  workDir?: string;
}): McpToolContext {
  return {
    services: {
      linear: createMockLinearService(overrides?.linear),
      session: createMockSessionService(overrides?.session),
      gatekeeper: createMockGatekeeperService(overrides?.gatekeeper),
    },
    io: createMockIo(),
    workDir: overrides?.workDir ?? "/work",
    logger: createMockLogger(),
  };
}

export function getLinearMocks(context: McpToolContext) {
  return {
    createFeatureRequest: context.services.linear.createFeatureRequest as ReturnType<typeof vi.fn>,
    getIssue: context.services.linear.getIssue as ReturnType<typeof vi.fn>,
    getIssueComments: context.services.linear.getIssueComments as ReturnType<typeof vi.fn>,
    createComment: context.services.linear.createComment as ReturnType<typeof vi.fn>,
  };
}

export async function createMcpTestClient(
  deps: McpServerDeps,
): Promise<{ client: Client; cleanup: () => Promise<void> }> {
  const server = createMcpServer(deps);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1.0.0" });
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  return {
    client,
    cleanup: async () => {
      await client.close();
      await server.close();
    },
  };
}
