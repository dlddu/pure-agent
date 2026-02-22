import { join } from "node:path";
import { z } from "zod";
import { DEFAULT_WORK_DIR, DEFAULT_TMP_DIR, EXPORT_CONFIG_FILENAME, ACTION_RESULTS_FILENAME, WORKSPACE_ZIP_FILENAME } from "./constants.js";

const ConfigSchema = z.object({
  WORK_DIR: z.string().default(DEFAULT_WORK_DIR),
  TMP_DIR: z.string().default(DEFAULT_TMP_DIR),
  LINEAR_API_KEY: z.string().min(1, "LINEAR_API_KEY is required"),
  GITHUB_TOKEN: z.string().optional(),
  LINEAR_API_URL: z.string().optional(),
});

export interface AppConfig {
  workDir: string;
  tmpDir: string;
  linearApiKey: string;
  githubToken?: string;
  linearApiUrl?: string;
}

export interface AppPaths {
  exportConfigPath: string;
  argoOutputPath: string;
  actionResultsOutputPath: string;
  zipOutputPath: string;
}

export function derivePaths(config: AppConfig): AppPaths {
  return {
    exportConfigPath: join(config.workDir, EXPORT_CONFIG_FILENAME),
    argoOutputPath: join(config.tmpDir, EXPORT_CONFIG_FILENAME),
    actionResultsOutputPath: join(config.tmpDir, ACTION_RESULTS_FILENAME),
    zipOutputPath: join(config.tmpDir, WORKSPACE_ZIP_FILENAME),
  };
}

export function deriveFallbackArgoPaths(
  env: Record<string, string | undefined> = process.env,
): { exportConfigPath: string; argoOutputPath: string } {
  const workDir = env.WORK_DIR || DEFAULT_WORK_DIR;
  const tmpDir = env.TMP_DIR || DEFAULT_TMP_DIR;
  return {
    exportConfigPath: join(workDir, EXPORT_CONFIG_FILENAME),
    argoOutputPath: join(tmpDir, EXPORT_CONFIG_FILENAME),
  };
}

export function parseConfig(
  env: Record<string, string | undefined> = process.env,
): AppConfig {
  const parsed = ConfigSchema.parse(env);
  return Object.freeze({
    workDir: parsed.WORK_DIR,
    tmpDir: parsed.TMP_DIR,
    linearApiKey: parsed.LINEAR_API_KEY,
    githubToken: parsed.GITHUB_TOKEN,
    linearApiUrl: parsed.LINEAR_API_URL,
  });
}
