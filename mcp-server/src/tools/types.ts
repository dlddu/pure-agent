import type { z } from "zod";
import type { ILinearService, ISessionService, IGatekeeperService, IExchangeRatesService } from "../services/types.js";
import type { IoLayer } from "../io.js";
import type { Logger } from "../logger.js";

export type McpToolMeta = {
  issueId?: string;
};

export type McpToolExtra = {
  requestId: string | number;
  sessionId?: string;
  signal: AbortSignal;
};

export type McpToolResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
  _meta?: McpToolMeta;
};

export interface McpToolContext {
  services: {
    linear: ILinearService;
    session: ISessionService;
    gatekeeper: IGatekeeperService;
    exchangeRates: IExchangeRatesService;
  };
  io: IoLayer;
  workDir: string;
  logger: Logger;
}

export interface McpTool {
  name: string;
  description: string;
  schema: z.ZodType;
  handler: (args: unknown, context: McpToolContext, extra?: McpToolExtra) => Promise<McpToolResponse> | McpToolResponse;
}
