import { describe, it, expect, vi } from "vitest";

const { mockExistsSync, mockCopyFileSync, mockWriteFileSync } = vi.hoisted(
  () => ({
    mockExistsSync: vi.fn(),
    mockCopyFileSync: vi.fn(),
    mockWriteFileSync: vi.fn(),
  }),
);

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    existsSync: mockExistsSync,
    copyFileSync: mockCopyFileSync,
    writeFileSync: mockWriteFileSync,
  };
});

import { ensureArgoOutput, writeActionResults } from "./argo-output.js";

describe("ensureArgoOutput", () => {
  it("copies export_config.json to argo output path when file exists", () => {
    mockExistsSync.mockReturnValue(true);

    ensureArgoOutput("/test/work/export_config.json", "/test/tmp/export_config.json");

    expect(mockCopyFileSync).toHaveBeenCalledWith(
      "/test/work/export_config.json",
      "/test/tmp/export_config.json",
    );
    expect(mockWriteFileSync).not.toHaveBeenCalled();
  });

  it("writes empty JSON when export_config.json does not exist", () => {
    mockExistsSync.mockReturnValue(false);

    ensureArgoOutput("/test/work/export_config.json", "/test/tmp/export_config.json");

    expect(mockWriteFileSync).toHaveBeenCalledWith("/test/tmp/export_config.json", "{}", "utf-8");
    expect(mockCopyFileSync).not.toHaveBeenCalled();
  });
});

describe("writeActionResults", () => {
  it("writes JSON-serialized results to the given path", () => {
    writeActionResults("/test/tmp/action_results.json", { pr_url: "https://example.com" });
    expect(mockWriteFileSync).toHaveBeenCalledWith(
      "/test/tmp/action_results.json",
      '{"pr_url":"https://example.com"}',
      "utf-8",
    );
  });

  it("writes empty JSON object when results are empty", () => {
    writeActionResults("/test/tmp/action_results.json", {});
    expect(mockWriteFileSync).toHaveBeenCalledWith(
      "/test/tmp/action_results.json",
      "{}",
      "utf-8",
    );
  });
});
