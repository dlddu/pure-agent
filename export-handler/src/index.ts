import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { LinearClient } from "@linear/sdk";
import { ExportConfigSchema, type ExportConfig } from "./schema.js";
import { ensureArgoOutput, writeActionResults } from "./services/argo-output.js";
import { processExport } from "./orchestrator.js";
import { parseConfig, derivePaths, deriveFallbackArgoPaths } from "./config.js";
import { createLogger } from "./logger.js";

const log = createLogger("export-handler");

function loadExportConfig(configPath: string): ExportConfig {
  const raw = readFileSync(configPath, "utf-8");
  return ExportConfigSchema.parse(JSON.parse(raw));
}

export async function run(): Promise<void> {
  log.info("Export handler started");

  const appConfig = parseConfig();
  const paths = derivePaths(appConfig);

  if (!existsSync(paths.exportConfigPath)) {
    log.info("No export_config.json found. Skipping export actions.");
    return;
  }

  const exportConfig = loadExportConfig(paths.exportConfigPath);
  log.info(`Export config loaded: actions=[${exportConfig.actions.join(",")}], issue=${exportConfig.linear_issue_id ?? "(none)"}`);

  const linearClient = new LinearClient({ apiKey: appConfig.linearApiKey, ...(appConfig.linearApiUrl && { apiUrl: appConfig.linearApiUrl }) });

  const actionResults = await processExport(exportConfig, linearClient, {
    workDir: appConfig.workDir,
    zipOutputPath: paths.zipOutputPath,
    githubToken: appConfig.githubToken,
  });

  // Copy export_config.json to /tmp for Argo output parameter
  ensureArgoOutput(paths.exportConfigPath, paths.argoOutputPath);

  // Write action results to /tmp for Argo output parameter
  writeActionResults(paths.actionResultsOutputPath, actionResults);

  log.info("Export handler completed successfully");
}

if (process.env.NODE_ENV !== "test") {
  run().catch((error) => {
    log.error("Export handler failed:", error);
    try {
      const { exportConfigPath, argoOutputPath } = deriveFallbackArgoPaths();
      ensureArgoOutput(exportConfigPath, argoOutputPath);
      writeActionResults(join(process.env.TMP_DIR || "/tmp", "action_results.json"), {});
    } catch (fallbackError) {
      console.error("Fallback Argo output failed:", fallbackError);
    }
    process.exit(1);
  });
}
