import { join } from "node:path";
import { createLogger } from "../logger.js";
import type { ISessionService, SessionServiceOptions, SessionInfo, SessionSource } from "./types.js";

const log = createLogger("session");

interface OutputFileEntry {
  filename: string;
  source: SessionSource;
}

export class SessionService implements ISessionService {
  private workDir: string;
  private readFile: (path: string, encoding: BufferEncoding) => Promise<string>;
  private stat: (path: string) => Promise<{ mtimeMs: number }>;
  private delayMs: number;

  private static OUTPUT_FILES: readonly OutputFileEntry[] = [
    { filename: "last_agent_output.json", source: "agent" },
    { filename: "last_planner_output.json", source: "planner" },
  ] as const;

  constructor(options: SessionServiceOptions) {
    this.workDir = options.workDir;
    this.readFile = options.readFile;
    this.stat = options.stat;
    this.delayMs = options.delayMs ?? 5_000;
  }

  async readSessionId(): Promise<SessionInfo | undefined> {
    if (this.delayMs > 0) {
      log.info("Waiting before reading session ID", { delayMs: this.delayMs });
      await new Promise((resolve) => setTimeout(resolve, this.delayMs));
    }
    const best = await this.mostRecentOutputFile();
    if (!best) {
      log.warn("No output files found", { workDir: this.workDir });
      return undefined;
    }
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
    let content: string;
    try {
      content = await this.readFile(filePath, "utf-8");
    } catch (error) {
      log.warn("Failed to read output file", { filePath, error });
      return undefined;
    }

    const firstLine = content.split("\n")[0].trim();
    if (!firstLine) {
      log.warn("Output file is empty", { filePath });
      return undefined;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(firstLine);
    } catch {
      log.warn("First line is not valid JSON", { filePath, firstLine: firstLine.slice(0, 120) });
      return undefined;
    }

    const sessionId = (parsed as Record<string, unknown>)?.session_id;
    if (typeof sessionId !== "string") {
      log.warn("session_id field missing or not a string", { filePath, sessionIdType: typeof sessionId });
      return undefined;
    }

    return sessionId;
  }
}
