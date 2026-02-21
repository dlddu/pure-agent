import express, { Request, Response } from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createLogger } from "./logger.js";
import { SERVER_VERSION } from "./version.js";

/**
 * Standard JSON-RPC 2.0 error codes.
 * @see https://www.jsonrpc.org/specification#error_object
 */
const JSON_RPC_INTERNAL_ERROR = -32603;
const JSON_RPC_SERVER_ERROR = -32000;

const log = createLogger("transport");

export function createHttpTransport(createServer: () => McpServer, mcpPath: string): express.Application {
  const app = express();

  app.use(express.json());

  app.use((req: Request, res: Response, next) => {
    const start = performance.now();
    res.on("finish", () => {
      const durationMs = Math.round(performance.now() - start);
      log.debug("HTTP request", { method: req.method, path: req.path, status: res.statusCode, durationMs });
    });
    next();
  });

  app.get("/health", (_req: Request, res: Response) => {
    res.json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: SERVER_VERSION,
    });
  });

  app.get("/ready", (_req: Request, res: Response) => {
    res.json({
      ready: true,
      timestamp: new Date().toISOString(),
    });
  });

  app.post(mcpPath, async (req: Request, res: Response) => {
    const mcpServer = createServer();
    try {
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
      });
      await mcpServer.connect(transport);
      await transport.handleRequest(req, res, req.body);
      res.on("close", () => {
        transport.close();
        mcpServer.close();
      });
    } catch (error) {
      const method = req.body?.method ?? "unknown";
      log.error("Error handling MCP request", { method, error });
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: "2.0",
          error: {
            code: JSON_RPC_INTERNAL_ERROR,
            message: "Internal server error",
          },
          id: null,
        });
      }
    }
  });

  function methodNotAllowed(_req: Request, res: Response) {
    res.status(405).json({
      jsonrpc: "2.0",
      error: {
        code: JSON_RPC_SERVER_ERROR,
        message: "Method not allowed.",
      },
      id: null,
    });
  }

  app.get(mcpPath, methodNotAllowed);
  app.delete(mcpPath, methodNotAllowed);

  return app;
}
