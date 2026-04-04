import { join } from "node:path";
import type { ISessionService, SessionServiceOptions, SessionInfo, SessionSource } from "./types.js";

interface OutputFileEntry {
  filename: string;
  source: SessionSource;
}

export class SessionService implements ISessionService {
  private workDir: string;
  private readFile: (path: string, encoding: BufferEncoding) => Promise<string>;
  private stat: (path: string) => Promise<{ mtimeMs: number }>;

  private static OUTPUT_FILES: readonly OutputFileEntry[] = [
    { filename: "last_agent_output.json", source: "agent" },
    { filename: "last_planner_output.json", source: "planner" },
  ] as const;

  constructor(options: SessionServiceOptions) {
    this.workDir = options.workDir;
    this.readFile = options.readFile;
    this.stat = options.stat;
  }

  async readSessionId(): Promise<SessionInfo | undefined> {
    const best = await this.mostRecentOutputFile();
    if (!best) return undefined;
    const sessionId = await this.extractSessionId(best.path);
    if (!sessionId) return undefined;
    return { sessionId, source: best.source };
  }

  private async mostRecentOutputFile(): Promise<{ path: string; source: SessionSource; mtimeMs: number } | undefined> {
    let best: { path: string; source: SessionSource; mtimeMs: number } | undefined;

    for (const entry of SessionService.OUTPUT_FILES) {
      const fullPath = join(this.workDir, entry.filename);
      try {
        const { mtimeMs } = await this.stat(fullPath);
        if (!best || mtimeMs > best.mtimeMs) {
          best = { path: fullPath, source: entry.source, mtimeMs };
        }
      } catch {
        // File does not exist — skip
      }
    }

    return best;
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
