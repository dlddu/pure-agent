import type { IoLayer } from "../io.js";

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
