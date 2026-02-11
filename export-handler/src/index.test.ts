import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExportConfig } from "./schema.js";

// Mock fs
const { mockExistsSync, mockCopyFileSync, mockWriteFileSync, mockReadFileSync } = vi.hoisted(
  () => ({
    mockExistsSync: vi.fn(),
    mockCopyFileSync: vi.fn(),
    mockWriteFileSync: vi.fn(),
    mockReadFileSync: vi.fn(),
  }),
);

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    existsSync: mockExistsSync,
    copyFileSync: mockCopyFileSync,
    writeFileSync: mockWriteFileSync,
    readFileSync: mockReadFileSync,
  };
});

// Mock action modules
const { mockPostSummary } = vi.hoisted(() => ({
  mockPostSummary: vi.fn().mockResolvedValue(undefined),
}));

const { mockUploadWorkspace } = vi.hoisted(() => ({
  mockUploadWorkspace: vi.fn().mockResolvedValue(undefined),
}));

const { mockPostReport } = vi.hoisted(() => ({
  mockPostReport: vi.fn().mockResolvedValue(undefined),
}));

const { mockCreatePr } = vi.hoisted(() => ({
  mockCreatePr: vi.fn().mockResolvedValue("https://github.com/org/repo/pull/1"),
}));

vi.mock("./actions/post-summary.js", () => ({
  postSummary: mockPostSummary,
}));

vi.mock("./actions/upload-workspace.js", () => ({
  uploadWorkspace: mockUploadWorkspace,
}));

vi.mock("./actions/post-report.js", () => ({
  postReport: mockPostReport,
}));

vi.mock("./actions/create-pr.js", () => ({
  createPr: mockCreatePr,
}));

// Mock LinearClient
vi.mock("@linear/sdk", () => ({
  LinearClient: vi.fn().mockImplementation(() => ({
    createComment: vi.fn().mockResolvedValue({ success: true }),
  })),
}));

import { ensureArgoOutput, processExport } from "./index.js";

function createMockLinearClient() {
  return {
    createComment: vi.fn().mockResolvedValue({ success: true }),
    fileUpload: vi.fn(),
  } as any;
}

describe("ensureArgoOutput", () => {
  beforeEach(() => {
    mockExistsSync.mockReset();
    mockCopyFileSync.mockReset();
    mockWriteFileSync.mockReset();
  });

  it("copies cycle_output.json to argo output path when file exists", () => {
    mockExistsSync.mockReturnValue(true);

    ensureArgoOutput();

    expect(mockCopyFileSync).toHaveBeenCalledWith(
      "/work/cycle_output.json",
      "/tmp/cycle_output.json",
    );
    expect(mockWriteFileSync).not.toHaveBeenCalled();
  });

  it("writes empty JSON when cycle_output.json does not exist", () => {
    mockExistsSync.mockReturnValue(false);

    ensureArgoOutput();

    expect(mockWriteFileSync).toHaveBeenCalledWith("/tmp/cycle_output.json", "{}", "utf-8");
    expect(mockCopyFileSync).not.toHaveBeenCalled();
  });
});

describe("processExport", () => {
  beforeEach(() => {
    mockPostSummary.mockReset().mockResolvedValue(undefined);
    mockUploadWorkspace.mockReset().mockResolvedValue(undefined);
    mockPostReport.mockReset().mockResolvedValue(undefined);
    mockCreatePr.mockReset().mockResolvedValue("https://github.com/org/repo/pull/1");
  });

  describe('linear_issue_id가 "none"인 경우', () => {
    const noneConfig: ExportConfig = {
      linear_issue_id: "none",
      summary: "이슈 없이 작업 완료",
      action: "none",
    };

    it("Linear API를 호출하지 않고 즉시 리턴한다", async () => {
      const client = createMockLinearClient();

      await processExport(noneConfig, client);

      expect(mockPostSummary).not.toHaveBeenCalled();
      expect(mockUploadWorkspace).not.toHaveBeenCalled();
      expect(mockPostReport).not.toHaveBeenCalled();
      expect(mockCreatePr).not.toHaveBeenCalled();
    });

    it("에러 없이 정상 완료된다", async () => {
      const client = createMockLinearClient();

      await expect(processExport(noneConfig, client)).resolves.toBeUndefined();
    });

    it("summary 값과 관계없이 Linear 호출을 스킵한다", async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        linear_issue_id: "none",
        summary: "매우 긴 요약 내용이 포함되어도 Linear API는 호출되지 않아야 합니다.",
        action: "none",
      };

      await processExport(config, client);

      expect(mockPostSummary).not.toHaveBeenCalled();
    });
  });

  describe("유효한 linear_issue_id인 경우", () => {
    const validConfig: ExportConfig = {
      linear_issue_id: "TEAM-123",
      summary: "작업 완료",
      action: "none",
    };

    it('action="none"이면 postSummary만 호출한다', async () => {
      const client = createMockLinearClient();

      await processExport(validConfig, client);

      expect(mockPostSummary).toHaveBeenCalledWith(client, "TEAM-123", "작업 완료");
      expect(mockUploadWorkspace).not.toHaveBeenCalled();
      expect(mockPostReport).not.toHaveBeenCalled();
      expect(mockCreatePr).not.toHaveBeenCalled();
    });

    it('action="upload_workspace"이면 postSummary + uploadWorkspace를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        action: "upload_workspace",
      };

      await processExport(config, client);

      expect(mockPostSummary).toHaveBeenCalledOnce();
      expect(mockUploadWorkspace).toHaveBeenCalledWith(client, "TEAM-123", "/work");
    });

    it('action="report"이면 postSummary + postReport를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        action: "report",
        report_content: "# 분석 결과\n\n문제 없음",
      };

      await processExport(config, client);

      expect(mockPostSummary).toHaveBeenCalledOnce();
      expect(mockPostReport).toHaveBeenCalledWith(client, "TEAM-123", "# 분석 결과\n\n문제 없음");
    });

    it('action="report"에 report_content가 없으면 에러를 던진다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        action: "report",
      };

      await expect(processExport(config, client)).rejects.toThrow(
        "report_content is required for action 'report'",
      );
    });

    it('action="create_pr"이면 postSummary + createPr를 호출한다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        action: "create_pr",
        pr: {
          title: "feat: 새 기능",
          body: "새 기능 추가",
          branch: "feature/new",
          base: "main",
        },
      };

      await processExport(config, client);

      expect(mockPostSummary).toHaveBeenCalledOnce();
      expect(mockCreatePr).toHaveBeenCalledWith(
        config.pr,
        "TEAM-123",
        client,
      );
    });

    it('action="create_pr"에 pr 설정이 없으면 에러를 던진다', async () => {
      const client = createMockLinearClient();
      const config: ExportConfig = {
        ...validConfig,
        action: "create_pr",
      };

      await expect(processExport(config, client)).rejects.toThrow(
        "pr config is required for action 'create_pr'",
      );
    });
  });
});
