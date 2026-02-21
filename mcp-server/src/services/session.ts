import { join } from "node:path";
import type { ISessionService, SessionServiceOptions } from "./types.js";

export class SessionService implements ISessionService {
  private workDir: string;
  private readFile: (path: string, encoding: BufferEncoding) => Promise<string>;

  constructor(options: SessionServiceOptions) {
    this.workDir = options.workDir;
    this.readFile = options.readFile;
  }

  async readSessionId(): Promise<string | undefined> {
    try {
      const filePath = join(this.workDir, "last_agent_output.json");
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
