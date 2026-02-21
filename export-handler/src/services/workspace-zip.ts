import { execFileSync as _execFileSync } from "node:child_process";
import { readFileSync as _readFileSync, statSync as _statSync } from "node:fs";
import type { LinearClient } from "@linear/sdk";
import { wrapError } from "../errors.js";
import { ZIP_EXCLUDE_PATTERNS } from "../constants.js";

export interface ZipResult {
  zipBuffer: Buffer;
  zipSizeBytes: number;
}

export interface ZipDeps {
  execFileSync: typeof _execFileSync;
  readFileSync: typeof _readFileSync;
  statSync: typeof _statSync;
}

const defaultZipDeps: ZipDeps = {
  execFileSync: _execFileSync,
  readFileSync: _readFileSync,
  statSync: _statSync,
};

export interface UploadToLinearOptions {
  linearClient: LinearClient;
  zipBuffer: Buffer;
  zipSizeBytes: number;
  filename: string;
}

export interface UploadDeps {
  fetch: typeof globalThis.fetch;
}

const defaultUploadDeps: UploadDeps = { fetch: globalThis.fetch };

export function createWorkspaceZip(
  workDir: string,
  zipOutputPath: string,
  deps: ZipDeps = defaultZipDeps,
): ZipResult {
  try {
    deps.execFileSync("zip", ["-r", zipOutputPath, ".", "-x", ...ZIP_EXCLUDE_PATTERNS], {
      cwd: workDir,
      stdio: "pipe",
    });

    return {
      zipBuffer: deps.readFileSync(zipOutputPath),
      zipSizeBytes: deps.statSync(zipOutputPath).size,
    };
  } catch (error) {
    throw wrapError(error, "Failed to create workspace zip");
  }
}

export async function uploadToLinear(
  opts: UploadToLinearOptions,
  deps: UploadDeps = defaultUploadDeps,
): Promise<string> {
  const { linearClient, zipBuffer, zipSizeBytes, filename } = opts;

  const uploadPayload = await linearClient.fileUpload(
    "application/zip",
    filename,
    zipSizeBytes,
  );

  const uploadFile = uploadPayload.uploadFile;
  if (!uploadFile) {
    throw new Error("Failed to get upload URL from Linear");
  }

  const headers: Record<string, string> = {
    ...Object.fromEntries(uploadFile.headers.map(({ key, value }) => [key, value])),
    "Content-Type": "application/zip",
  };

  const uploadResponse = await deps.fetch(uploadFile.uploadUrl, {
    method: "PUT",
    headers,
    body: new Uint8Array(zipBuffer),
  });

  if (!uploadResponse.ok) {
    const responseBody = await uploadResponse.text().catch(() => "");
    throw wrapError(
      new Error(`${uploadResponse.status} ${uploadResponse.statusText}${responseBody ? ` - ${responseBody}` : ""}`),
      "Failed to upload zip to Linear",
    );
  }

  return uploadFile.assetUrl;
}
