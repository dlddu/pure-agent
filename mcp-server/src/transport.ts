import express, { Request, Response } from "express";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

export async function createHttpTransport(mcpServer: Server, mcpPath: string): Promise<express.Application> {
  const app = express();

  app.use(express.json());

  app.get("/health", (_req: Request, res: Response) => {
    res.json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: "1.0.0",
    });
  });

  app.get("/ready", (_req: Request, res: Response) => {
    res.json({
      ready: true,
      timestamp: new Date().toISOString(),
    });
  });

  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });

  await mcpServer.connect(transport);

  app.post(mcpPath, async (req: Request, res: Response) => {
    await transport.handleRequest(req, res, req.body);
  });

  return app;
}
