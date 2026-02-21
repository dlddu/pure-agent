import type { z } from "zod";
import type { ILinearService, ISessionService } from "../services/types.js";
import type { Logger } from "../logger.js";

export type McpToolMeta = {
  issueId?: string;
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
  };
  fs: {
    writeFile(path: string, data: string, encoding: BufferEncoding): Promise<void>;
    readFile(path: string, encoding: BufferEncoding): Promise<string>;
    access(path: string): Promise<void>;
  };
  exec: {
    execFile(
      file: string,
      args: string[],
      options: { cwd: string; timeout: number; maxBuffer: number },
    ): Promise<{ stdout: string; stderr: string }>;
  };
  workDir: string;
  logger: Logger;
}

export interface McpTool {
  name: string;
  description: string;
  schema: z.ZodType;
  handler: (args: unknown, context: McpToolContext) => Promise<McpToolResponse> | McpToolResponse;
}
