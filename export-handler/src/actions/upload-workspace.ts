import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import type { LinearClient } from "@linear/sdk";

const ZIP_OUTPUT_PATH = "/tmp/workspace.zip";

const EXCLUDE_PATTERNS = [
  ".git/*",
  "node_modules/*",
  "export_config.json",
  "cycle_output.json",
];

export async function uploadWorkspace(
  client: LinearClient,
  issueId: string,
  workDir: string
): Promise<void> {
  // Create zip
  execFileSync("zip", ["-r", ZIP_OUTPUT_PATH, ".", "-x", ...EXCLUDE_PATTERNS], {
    cwd: workDir,
    stdio: "pipe",
  });

  const zipBuffer = readFileSync(ZIP_OUTPUT_PATH);
  const zipSize = statSync(ZIP_OUTPUT_PATH).size;
  const filename = `workspace-${Date.now()}.zip`;

  console.log(`Workspace zip created: ${(zipSize / 1024 / 1024).toFixed(2)} MB`);

  // Request upload URL from Linear
  const uploadPayload = await client.fileUpload(
    "application/zip",
    filename,
    zipSize
  );

  const uploadFile = uploadPayload.uploadFile;
  if (!uploadFile) {
    throw new Error("Failed to get upload URL from Linear");
  }

  // Upload zip to presigned URL
  const headers: Record<string, string> = {};
  for (const { key, value } of uploadFile.headers) {
    headers[key] = value;
  }
  headers["Content-Type"] = "application/zip";

  const uploadResponse = await fetch(uploadFile.uploadUrl, {
    method: "PUT",
    headers,
    body: zipBuffer,
  });

  if (!uploadResponse.ok) {
    throw new Error(`Failed to upload zip: ${uploadResponse.status} ${uploadResponse.statusText}`);
  }

  // Post comment with download link
  const body = `## Workspace 압축 파일\n\n작업 workspace 전체가 첨부되었습니다.\n\n[${filename}](${uploadFile.assetUrl})`;

  const commentResult = await client.createComment({
    issueId,
    body,
  });

  if (!commentResult.success) {
    throw new Error("Failed to create upload comment on Linear issue");
  }
}
