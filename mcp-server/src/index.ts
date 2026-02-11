import "dotenv/config";
import { z } from "zod";
import { createMcpServer } from "./server.js";
import { createHttpTransport } from "./transport.js";
import { LinearService } from "./services/linear.js";

const ConfigSchema = z.object({
  PORT: z.coerce.number().default(8080),
  HOST: z.string().default("0.0.0.0"),
  MCP_PATH: z.string().default("/mcp"),
  LINEAR_API_KEY: z.string().min(1, "LINEAR_API_KEY is required"),
  LINEAR_TEAM_ID: z.string().min(1, "LINEAR_TEAM_ID is required"),
  LINEAR_DEFAULT_PROJECT_ID: z.string().optional(),
  LINEAR_DEFAULT_LABEL_ID: z.string().optional(),
});

async function main() {
  const config = ConfigSchema.parse(process.env);

  console.log("Starting Pure-Agent MCP Server...");
  console.log(`Configuration: PORT=${config.PORT}, HOST=${config.HOST}`);

  const linearService = new LinearService({
    apiKey: config.LINEAR_API_KEY,
    teamId: config.LINEAR_TEAM_ID,
    defaultProjectId: config.LINEAR_DEFAULT_PROJECT_ID,
    defaultLabelId: config.LINEAR_DEFAULT_LABEL_ID,
  });

  console.log("Initializing MCP server...");

  const app = createHttpTransport(() => createMcpServer(linearService), config.MCP_PATH);

  app.listen(config.PORT, config.HOST, () => {
    console.log(`MCP Server listening on http://${config.HOST}:${config.PORT}`);
    console.log(`MCP endpoint: http://${config.HOST}:${config.PORT}${config.MCP_PATH}`);
    console.log(`Health check: http://${config.HOST}:${config.PORT}/health`);
  });
}

process.on("SIGTERM", () => {
  console.log("Received SIGTERM, shutting down gracefully...");
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log("Received SIGINT, shutting down gracefully...");
  process.exit(0);
});

main().catch((error) => {
  console.error("Failed to start MCP server:", error);
  process.exit(1);
});
