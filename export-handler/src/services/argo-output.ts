import { existsSync, copyFileSync, writeFileSync } from "node:fs";
import type { ActionResult } from "../actions/types.js";

export function ensureArgoOutput(
  exportConfigPath: string,
  argoOutputPath: string,
): void {
  if (existsSync(exportConfigPath)) {
    copyFileSync(exportConfigPath, argoOutputPath);
  } else {
    writeFileSync(argoOutputPath, "{}", "utf-8");
  }
}

export function writeActionResults(
  outputPath: string,
  results: ActionResult,
): void {
  writeFileSync(outputPath, JSON.stringify(results), "utf-8");
}
