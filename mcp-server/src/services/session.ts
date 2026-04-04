import { join } from "node:path";
import type { ISessionService, SessionServiceOptions } from "./types.js";

export class SessionService implements ISessionService {
  private workDir: string;
  private readFile: (path: string, encoding: BufferEncoding) => Promise<string>;
  private stat: (path: string) => Promise<{ mtimeMs: number }>;

  private static OUTPUT_FILES = [
    "last_agent_output.json",
    "last_planner_output.json",
  ] as const;

  constructor(options: SessionServiceOptions) {
    this.workDir = options.workDir;
    this.readFile = options.readFile;
    this.stat = options.stat;
  }

  async readSessionId(): Promise<string | undefined> {
    const filePath = await this.mostRecentOutputFile();
    if (!filePath) return undefined;
    return this.extractSessionId(filePath);
  }

  private async mostRecentOutputFile(): Promise<string | undefined> {
    let best: { path: string; mtimeMs: number } | undefined;

    for (const file of SessionService.OUTPUT_FILES) {
      const fullPath = join(this.workDir, file);
      try {
        const { mtimeMs } = await this.stat(fullPath);
        if (!best || mtimeMs > best.mtimeMs) {
          best = { path: fullPath, mtimeMs };
        }
      } catch {
        // File does not exist — skip
      }
    }

    return best?.path;
  }

  private async extractSessionId(filePath: string): Promise<string | undefined> {
    try {
      const content = await this.readFile(filePath, "utf-8");
      const firstLine = content.split("\n")[0].trim();
      if (!firstLine) return undefined;
      const parsed = JSON.parse(firstLine);
      return typeof parsed?.session_id === "string" ? parsed.session_id : undefined;
    } catch {
      return undefined;
    }
  }
}
