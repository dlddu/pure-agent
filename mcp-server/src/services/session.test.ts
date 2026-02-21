import { describe, it, expect, vi, beforeEach } from "vitest";
import { SessionService } from "./session.js";

describe("SessionService", () => {
  let service: SessionService;
  let mockReadFile: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockReadFile = vi.fn();
    service = new SessionService({ workDir: "/work", readFile: mockReadFile });
  });

  describe("readSessionId", () => {
    it("returns session_id from valid JSON first line", async () => {
      mockReadFile.mockResolvedValue('{"type":"system","session_id":"sess-abc"}\n');
      await expect(service.readSessionId()).resolves.toBe("sess-abc");
    });

    it("returns undefined when file does not exist", async () => {
      mockReadFile.mockRejectedValue(new Error("ENOENT: no such file or directory"));
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when file is empty", async () => {
      mockReadFile.mockResolvedValue("");
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when first line is not valid JSON", async () => {
      mockReadFile.mockResolvedValue("not-json\n");
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when JSON has no session_id field", async () => {
      mockReadFile.mockResolvedValue('{"type":"system","other":"value"}\n');
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("returns undefined when session_id is not a string", async () => {
      mockReadFile.mockResolvedValue('{"session_id":123}\n');
      await expect(service.readSessionId()).resolves.toBeUndefined();
    });

    it("only parses the first line of multi-line content", async () => {
      mockReadFile.mockResolvedValue('{"session_id":"first"}\n{"session_id":"second"}\n');
      await expect(service.readSessionId()).resolves.toBe("first");
    });
  });
});
