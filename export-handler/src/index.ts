import { readFileSync, writeFileSync, copyFileSync, existsSync } from "node:fs";
import { LinearClient } from "@linear/sdk";
import { ExportConfigSchema, type ExportConfig } from "./schema.js";
import { postSummary } from "./actions/post-summary.js";
import { uploadWorkspace } from "./actions/upload-workspace.js";
import { postReport } from "./actions/post-report.js";
import { createPr } from "./actions/create-pr.js";

const WORK_DIR = "/work";
const EXPORT_CONFIG_PATH = `${WORK_DIR}/export_config.json`;
const CYCLE_OUTPUT_PATH = `${WORK_DIR}/cycle_output.json`;
const ARGO_OUTPUT_PATH = "/tmp/cycle_output.json";

export function ensureArgoOutput(): void {
  if (existsSync(CYCLE_OUTPUT_PATH)) {
    copyFileSync(CYCLE_OUTPUT_PATH, ARGO_OUTPUT_PATH);
  } else {
    writeFileSync(ARGO_OUTPUT_PATH, "{}", "utf-8");
  }
}

export async function processExport(
  config: ExportConfig,
  linearClient: LinearClient,
  workDir: string = WORK_DIR,
): Promise<void> {
  // linear_issue_id가 "none"이면 Linear API 호출을 스킵
  if (config.linear_issue_id === "none") {
    console.log("linear_issue_id is 'none'. Skipping Linear actions.");
    return;
  }

  // Step 1: Always post summary
  console.log("Posting summary comment to Linear...");
  await postSummary(linearClient, config.linear_issue_id, config.summary);
  console.log("Summary posted");

  // Step 2: Execute action branch
  switch (config.action) {
    case "none":
      console.log("Action: none. No additional work.");
      break;

    case "upload_workspace":
      console.log("Action: upload_workspace. Zipping and uploading...");
      await uploadWorkspace(linearClient, config.linear_issue_id, workDir);
      console.log("Workspace uploaded");
      break;

    case "report":
      if (!config.report_content) {
        throw new Error("report_content is required for action 'report'");
      }
      console.log("Action: report. Posting analysis report...");
      await postReport(linearClient, config.linear_issue_id, config.report_content);
      console.log("Report posted");
      break;

    case "create_pr":
      if (!config.pr) {
        throw new Error("pr config is required for action 'create_pr'");
      }
      console.log("Action: create_pr. Creating GitHub PR...");
      const prUrl = await createPr(config.pr, config.linear_issue_id, linearClient);
      console.log(`PR created: ${prUrl}`);
      break;
  }
}

async function main(): Promise<void> {
  console.log("Export handler started");

  // Always ensure Argo output parameter exists
  ensureArgoOutput();

  if (!existsSync(EXPORT_CONFIG_PATH)) {
    console.log("No export_config.json found. Skipping export actions.");
    return;
  }

  const raw = readFileSync(EXPORT_CONFIG_PATH, "utf-8");
  const config = ExportConfigSchema.parse(JSON.parse(raw));
  console.log(`Export config loaded: action=${config.action}, issue=${config.linear_issue_id}`);

  const apiKey = process.env.LINEAR_API_KEY;
  if (!apiKey) {
    throw new Error("LINEAR_API_KEY environment variable is required");
  }

  const linearClient = new LinearClient({ apiKey });

  await processExport(config, linearClient);

  console.log("Export handler completed successfully");
}

main().catch((error) => {
  console.error("Export handler failed:", error);
  // Ensure Argo output exists even on failure
  ensureArgoOutput();
  process.exit(1);
});
