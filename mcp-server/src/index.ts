import "dotenv/config";
import { writeFile, readFile, access, stat } from "node:fs/promises";
import { execFile as execFileCb } from "node:child_process";
import { promisify } from "node:util";
import { LinearClient } from "@linear/sdk";
import { S3Client } from "@aws-sdk/client-s3";
import { parquetReadObjects } from "hyparquet";
import { createMcpServer } from "./server.js";
import { createHttpTransport } from "./transport.js";
import { LinearService } from "./services/linear.js";
import { SessionService } from "./services/session.js";
import { GatekeeperService } from "./services/gatekeeper.js";
import { ExchangeRatesService } from "./services/exchange-rates.js";
import { createDefaultTools } from "./tools/registry.js";
import { sessionCommentHook } from "./hooks/post-tool-hooks.js";
import { createLogger } from "./logger.js";
import { parseConfig } from "./config.js";
import type { McpToolContext } from "./tools/types.js";

const execFileAsync = promisify(execFileCb);

const log = createLogger("mcp-server");

async function main() {
  const config = parseConfig();

  log.info("Starting Pure-Agent MCP Server...");
  log.info(`Configuration: PORT=${config.PORT}, HOST=${config.HOST}`);

  const linearService = new LinearService({
    client: new LinearClient({ apiKey: config.LINEAR_API_KEY, ...(config.LINEAR_API_URL && { apiUrl: config.LINEAR_API_URL }) }),
    teamId: config.LINEAR_TEAM_ID,
    defaultProjectId: config.LINEAR_DEFAULT_PROJECT_ID,
    defaultLabelId: config.LINEAR_DEFAULT_LABEL_ID,
  });

  log.info("Initializing MCP server...");

  const sessionService = new SessionService({ workDir: config.WORK_DIR, readFile, stat });

  const gatekeeperService = new GatekeeperService({
    gatekeeperUrl: config.GATEKEEPER_URL ?? "",
    apiKey: config.GATEKEEPER_API_KEY ?? "",
    userId: config.GATEKEEPER_USER_ID ?? "",
    pollIntervalMs: config.GATEKEEPER_POLL_INTERVAL_MS,
    timeoutMs: config.GATEKEEPER_TIMEOUT_MS,
    fetch: globalThis.fetch,
  });

  const s3Client = new S3Client({
    region: config.AWS_REGION,
    ...(config.AWS_ENDPOINT_URL && {
      endpoint: config.AWS_ENDPOINT_URL,
      forcePathStyle: true,
    }),
  });

  const exchangeRatesService = new ExchangeRatesService({
    s3Client,
    bucket: config.AWS_S3_BUCKET_NAME ?? "",
    readParquet: async (bytes) => {
      const file = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(file).set(bytes);
      return (await parquetReadObjects({ file })) as Record<string, unknown>[];
    },
    logger: createLogger("exchange-rates"),
  });

  const toolContext: McpToolContext = {
    services: {
      linear: linearService,
      session: sessionService,
      gatekeeper: gatekeeperService,
      exchangeRates: exchangeRatesService,
    },
    fs: { writeFile, readFile, access },
    exec: {
      execFile: async (file, args, options) => {
        const { stdout, stderr } = await execFileAsync(file, args, options);
        return { stdout, stderr };
      },
    },
    workDir: config.WORK_DIR,
    logger: createLogger("tools"),
    fetch: globalThis.fetch,
  };

  const tools = createDefaultTools();
  const app = createHttpTransport(
    () => createMcpServer({
      tools,
      context: toolContext,
      postToolHooks: [sessionCommentHook],
    }),
    config.MCP_PATH,
  );

  const server = app.listen(config.PORT, config.HOST, () => {
    log.info(`MCP Server listening on http://${config.HOST}:${config.PORT}`);
    log.info(`MCP endpoint: http://${config.HOST}:${config.PORT}${config.MCP_PATH}`);
    log.info(`Health check: http://${config.HOST}:${config.PORT}/health`);
  });

  const shutdown = () => {
    log.info("Shutting down gracefully...");
    server.close(() => {
      log.info("HTTP server closed");
      process.exit(0);
    });
    setTimeout(() => {
      log.warn("Forced shutdown after timeout");
      process.exit(1);
    }, 10_000).unref();
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((error) => {
  log.error("Failed to start MCP server:", error);
  process.exit(1);
});
