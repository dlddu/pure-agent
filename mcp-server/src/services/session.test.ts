import { describe, it, expect, vi, beforeEach } from "vitest";
import { SessionService } from "./session.js";

describe("SessionService", () => {
  let service: SessionService;
  let mockReadFile: ReturnType<typeof vi.fn>;
  let mockStat: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockReadFile = vi.fn();
    mockStat = vi.fn();
    service = new SessionService({ workDir: "/work", readFile: mockReadFile, stat: mockStat });
  });

  describe("readSessionId", () => {
    it("returns session_id from valid JSON first line", async () => {
      mockStat.mockImplementation((path: string) => {
        if (path === "/work/last_agent_output.json") return Promise.resolve({ mtimeMs: 1000 });
        return Promise.reject(new Error("ENOENT"));
      });
      mockReadFile.mockResolvedValue('{"type":"system","session_id":"sess-abc"}\n');
      await expect(service.readSessionId()).resolves.toBe("sess-abc");
    });

    it("returns undefined when no output files exist", async () => {
      mockStat.mockRejectedValue(new Error("ENOENT"));
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when file is empty", async () => {
      mockStat.mockResolvedValue({ mtimeMs: 1000 });
      mockReadFile.mockResolvedValue("");
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when first line is not valid JSON", async () => {
      mockStat.mockResolvedValue({ mtimeMs: 1000 });
      mockReadFile.mockResolvedValue("not-json\n");
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when JSON has no session_id field", async () => {
      mockStat.mockResolvedValue({ mtimeMs: 1000 });
      mockReadFile.mockResolvedValue('{"type":"system","other":"value"}\n');
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when session_id is not a string", async () => {
      mockStat.mockResolvedValue({ mtimeMs: 1000 });
      mockReadFile.mockResolvedValue('{"session_id":123}\n');
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("only parses the first line of multi-line content", async () => {
      mockStat.mockResolvedValue({ mtimeMs: 1000 });
      mockReadFile.mockResolvedValue('{"session_id":"first"}\n{"session_id":"second"}\n');
      await expect(service.readSessionId()).resolves.toBe("first");
    });

    it("prefers more recently modified file", async () => {
      mockStat.mockImplementation((path: string) => {
        if (path === "/work/last_agent_output.json") return Promise.resolve({ mtimeMs: 1000 });
        if (path === "/work/last_planner_output.json") return Promise.resolve({ mtimeMs: 2000 });
        return Promise.reject(new Error("ENOENT"));
      });
      mockReadFile.mockImplementation((path: string) => {
        if (path === "/work/last_planner_output.json") return Promise.resolve('{"session_id":"planner-sess"}\n');
        return Promise.resolve('{"session_id":"agent-sess"}\n');
      });
      await expect(service.readSessionId()).resolves.toBe("planner-sess");
    });

    it("falls back to agent file when planner file is missing", async () => {
      mockStat.mockImplementation((path: string) => {
        if (path === "/work/last_agent_output.json") return Promise.resolve({ mtimeMs: 1000 });
        return Promise.reject(new Error("ENOENT"));
      });
      mockReadFile.mockResolvedValue('{"session_id":"agent-only"}\n');
      await expect(service.readSessionId()).resolves.toBe("agent-only");
    });

    it("falls back to planner file when agent file is missing", async () => {
      mockStat.mockImplementation((path: string) => {
        if (path === "/work/last_planner_output.json") return Promise.resolve({ mtimeMs: 1000 });
        return Promise.reject(new Error("ENOENT"));
      });
      mockReadFile.mockImplementation((path: string) => {
        if (path === "/work/last_planner_output.json") return Promise.resolve('{"session_id":"planner-only"}\n');
        return Promise.reject(new Error("ENOENT"));
      });
      await expect(service.readSessionId()).resolves.toBe("planner-only");
    });
  });
});
