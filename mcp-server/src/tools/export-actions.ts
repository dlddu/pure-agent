import { z } from "zod";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const WORK_DIR = process.env.WORK_DIR || "/work";
const EXPORT_CONFIG_PATH = join(WORK_DIR, "export_config.json");

const EXPORT_ACTIONS = [
  {
    type: "none",
    description: "추가 작업 없음. 작업 요약 코멘트만 Linear 이슈에 추가됩니다.",
    required_fields: [],
  },
  {
    type: "upload_workspace",
    description:
      "workspace 전체를 압축하여 Linear 이슈에 첨부합니다. 코드, 데이터, 결과물 등을 공유할 때 사용합니다.",
    required_fields: [],
  },
  {
    type: "report",
    description:
      "분석 리포트를 Linear 이슈 코멘트로 추가합니다. 마크다운 형식의 상세 분석 결과를 공유할 때 사용합니다.",
    required_fields: ["report_content"],
  },
  {
    type: "create_pr",
    description:
      "GitHub Pull Request를 생성합니다. 코드 변경 사항을 리뷰 및 머지하기 위해 사용합니다.",
    required_fields: ["pr_title", "pr_body", "pr_branch"],
  },
] as const;

export const GET_EXPORT_ACTIONS_TOOL = {
  name: "get_export_actions",
  description:
    "사용 가능한 export action 목록을 조회합니다. 작업 완료 후 결과물을 내보내는 방법을 확인할 때 사용합니다.",
  inputSchema: {
    type: "object" as const,
    properties: {},
    required: [] as string[],
  },
};

const PrConfigSchema = z.object({
  title: z.string().min(1).max(200).describe("PR 제목"),
  body: z.string().max(10000).describe("PR 설명 (마크다운)"),
  branch: z.string().min(1).max(100).describe("소스 브랜치 이름"),
  base: z.string().max(100).optional().default("main").describe("타겟 브랜치 (기본값: main)"),
  repo: z.string().max(200).optional().describe("GitHub 저장소 (owner/name). 미입력 시 환경변수 GITHUB_REPO 사용"),
});

const SetExportConfigInputSchema = z.object({
  linear_issue_id: z
    .string()
    .min(1)
    .describe("Linear 이슈 ID. 이슈 ID를 알 수 없는 경우 'none'으로 설정."),
  summary: z
    .string()
    .min(1)
    .max(10000)
    .describe("작업 요약. Linear 이슈에 코멘트로 항상 추가됩니다."),
  action: z
    .enum(["none", "upload_workspace", "report", "create_pr"])
    .describe("수행할 export action 타입"),
  report_content: z
    .string()
    .max(50000)
    .optional()
    .describe("분석 리포트 마크다운 내용 (action=report일 때 필수)"),
  pr: PrConfigSchema.optional().describe("PR 설정 (action=create_pr일 때 필수)"),
});

export const SET_EXPORT_CONFIG_TOOL = {
  name: "set_export_config",
  description:
    "작업 완료 후 export 설정을 저장합니다. 이 설정에 따라 Linear 이슈에 코멘트가 추가되고, 선택한 action이 수행됩니다. 반드시 작업 완료 시점에 호출하세요.",
  inputSchema: {
    type: "object" as const,
    properties: {
      linear_issue_id: {
        type: "string",
        description: "Linear 이슈 ID. 이슈 ID를 알 수 없는 경우 'none'으로 설정.",
      },
      summary: {
        type: "string",
        description: "작업 요약. Linear 이슈에 코멘트로 항상 추가됩니다.",
        maxLength: 10000,
      },
      action: {
        type: "string",
        enum: ["none", "upload_workspace", "report", "create_pr"],
        description: "수행할 export action 타입",
      },
      report_content: {
        type: "string",
        description: "분석 리포트 마크다운 내용 (action=report일 때 필수)",
        maxLength: 50000,
      },
      pr: {
        type: "object",
        description: "PR 설정 (action=create_pr일 때 필수)",
        properties: {
          title: { type: "string", description: "PR 제목", maxLength: 200 },
          body: { type: "string", description: "PR 설명 (마크다운)", maxLength: 10000 },
          branch: { type: "string", description: "소스 브랜치 이름", maxLength: 100 },
          base: { type: "string", description: "타겟 브랜치 (기본값: main)", maxLength: 100 },
          repo: { type: "string", description: "GitHub 저장소 (owner/name)", maxLength: 200 },
        },
        required: ["title", "body", "branch"],
      },
    },
    required: ["linear_issue_id", "summary", "action"],
  },
};

export function handleGetExportActions(): {
  content: Array<{ type: "text"; text: string }>;
} {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify({ actions: EXPORT_ACTIONS }, null, 2),
      },
    ],
  };
}

export function handleSetExportConfig(args: unknown): {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
} {
  try {
    const validated = SetExportConfigInputSchema.parse(args);

    if (validated.action === "report" && !validated.report_content) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: false,
              error: "report_content is required when action is 'report'",
            }),
          },
        ],
        isError: true,
      };
    }

    if (validated.action === "create_pr" && !validated.pr) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: false,
              error: "pr config is required when action is 'create_pr'",
            }),
          },
        ],
        isError: true,
      };
    }

    writeFileSync(EXPORT_CONFIG_PATH, JSON.stringify(validated, null, 2), "utf-8");

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            success: true,
            message: `Export config saved. Action '${validated.action}' will be executed after the cycle completes.`,
            config_path: EXPORT_CONFIG_PATH,
          }),
        },
      ],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ success: false, error: errorMessage }),
        },
      ],
      isError: true,
    };
  }
}
