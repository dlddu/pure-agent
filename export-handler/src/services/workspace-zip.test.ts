import { describe, it, expect, vi } from "vitest";
import { createWorkspaceZip, uploadToLinear } from "./workspace-zip.js";
import type { ZipDeps, UploadDeps } from "./workspace-zip.js";
import { createMockLinearClient } from "../test-helpers.js";

function createMockZipDeps(overrides: Partial<ZipDeps> = {}): ZipDeps {
  return {
    execFileSync: vi.fn(),
    readFileSync: vi.fn().mockReturnValue(Buffer.from("fake-zip")),
    statSync: vi.fn().mockReturnValue({ size: 1024 }),
    ...overrides,
  };
}

function createMockUploadDeps(overrides: Partial<UploadDeps> = {}): UploadDeps {
  return {
    fetch: vi.fn().mockResolvedValue({ ok: true }),
    ...overrides,
  };
}

describe("createWorkspaceZip", () => {
  it("zip 명령어를 올바른 인자로 실행하고 결과를 반환한다", () => {
    const deps = createMockZipDeps();

    const result = createWorkspaceZip("/work", "/tmp/workspace.zip", deps);

    expect(deps.execFileSync).toHaveBeenCalledWith(
      "zip",
      ["-r", "/tmp/workspace.zip", ".", "-x", ".git/*", "node_modules/*", "export_config.json"],
      { cwd: "/work", stdio: "pipe" },
    );
    expect(result).toEqual({ zipBuffer: Buffer.from("fake-zip"), zipSizeBytes: 1024 });
  });

  it("zip 실행 실패 시 컨텍스트 포함 에러를 던진다", () => {
    const deps = createMockZipDeps({
      execFileSync: vi.fn(() => {
        throw new Error("zip not found");
      }),
    });

    expect(() => createWorkspaceZip("/work", "/tmp/workspace.zip", deps)).toThrow(
      "Failed to create workspace zip: zip not found",
    );
  });

  it("zip 파일 읽기 실패 시 컨텍스트 포함 에러를 던진다", () => {
    const deps = createMockZipDeps({
      readFileSync: vi.fn(() => {
        throw new Error("EACCES: permission denied");
      }),
    });

    expect(() => createWorkspaceZip("/work", "/tmp/workspace.zip", deps)).toThrow(
      "Failed to create workspace zip: EACCES: permission denied",
    );
  });
});

describe("uploadToLinear", () => {
  it("presigned URL로 업로드하고 assetUrl을 반환한다", async () => {
    const mockFetch = vi.fn().mockResolvedValue({ ok: true });
    const client = createMockLinearClient({
      fileUpload: vi.fn().mockResolvedValue({
        uploadFile: {
          uploadUrl: "https://upload.example.com",
          assetUrl: "https://asset.example.com/file.zip",
          headers: [{ key: "x-custom", value: "header-value" }],
        },
      }),
    });

    const result = await uploadToLinear(
      { linearClient: client, zipBuffer: Buffer.from("data"), zipSizeBytes: 100, filename: "test.zip" },
      { fetch: mockFetch },
    );

    expect(result).toBe("https://asset.example.com/file.zip");
    expect(mockFetch).toHaveBeenCalledWith("https://upload.example.com", {
      method: "PUT",
      headers: { "x-custom": "header-value", "Content-Type": "application/zip" },
      body: new Uint8Array(Buffer.from("data")),
    });
  });

  it("fileUpload가 uploadFile을 반환하지 않으면 에러를 던진다", async () => {
    const client = createMockLinearClient({
      fileUpload: vi.fn().mockResolvedValue({ uploadFile: undefined }),
    });

    await expect(
      uploadToLinear(
        { linearClient: client, zipBuffer: Buffer.from("data"), zipSizeBytes: 100, filename: "test.zip" },
        createMockUploadDeps(),
      ),
    ).rejects.toThrow("Failed to get upload URL from Linear");
  });

  it("업로드 응답이 실패하면 컨텍스트 포함 에러를 던진다", async () => {
    const client = createMockLinearClient({
      fileUpload: vi.fn().mockResolvedValue({
        uploadFile: {
          uploadUrl: "https://upload.example.com",
          assetUrl: "https://asset.example.com/file.zip",
          headers: [],
        },
      }),
    });
    const deps = createMockUploadDeps({
      fetch: vi.fn().mockResolvedValue({
        ok: false,
        status: 403,
        statusText: "Forbidden",
        text: () => Promise.resolve("Access denied"),
      }),
    });

    await expect(
      uploadToLinear(
        { linearClient: client, zipBuffer: Buffer.from("data"), zipSizeBytes: 100, filename: "test.zip" },
        deps,
      ),
    ).rejects.toThrow("Failed to upload zip to Linear: 403 Forbidden - Access denied");
  });
});
