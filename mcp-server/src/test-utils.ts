import { vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer, type McpServerDeps } from "./server.js";
import type { ISessionService, IGatekeeperService, IExchangeRatesService } from "./services/types.js";
import type { IoLayer } from "./io.js";
import type { McpToolContext, McpToolExtra } from "./tools/types.js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseResponseText(result: Record<string, any>) {
  return JSON.parse(result.content[0].text);
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

export function createMockExchangeRatesService(
  overrides?: Partial<Record<keyof IExchangeRatesService, ReturnType<typeof vi.fn>>>,
): IExchangeRatesService {
  return {
    listByDateRange: vi.fn().mockResolvedValue([]),
    getObject: vi.fn().mockResolvedValue(new Uint8Array()),
    ...overrides,
  } as IExchangeRatesService;
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
    writeBinaryFile: vi.fn().mockResolvedValue(undefined),
    mkdir: vi.fn().mockResolvedValue(undefined),
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
  session?: Partial<Record<keyof ISessionService, ReturnType<typeof vi.fn>>>;
  gatekeeper?: Partial<Record<keyof IGatekeeperService, ReturnType<typeof vi.fn>>>;
  exchangeRates?: Partial<Record<keyof IExchangeRatesService, ReturnType<typeof vi.fn>>>;
  workDir?: string;
}): McpToolContext {
  return {
    services: {
      session: createMockSessionService(overrides?.session),
      gatekeeper: createMockGatekeeperService(overrides?.gatekeeper),
      exchangeRates: createMockExchangeRatesService(overrides?.exchangeRates),
    },
    io: createMockIo(),
    workDir: overrides?.workDir ?? "/work",
    logger: createMockLogger(),
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
