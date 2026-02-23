import { z } from "zod";

// Export action types (keep in sync with export-handler)
export const EXPORT_ACTION_TYPES = ["none", "upload_workspace", "report", "create_pr", "continue"] as const;
export const EXPORT_CONFIG_FILENAME = "export_config.json";

/** Actions that must be the sole element when present in the actions array. */
export const EXCLUSIVE_ACTIONS = new Set(["none", "continue"]);

/** Actions that require a valid linear_issue_id. */
export const ACTIONS_REQUIRING_ISSUE = new Set(["upload_workspace", "report"]);

// Validation limits (keep in sync with export-handler/src/constants.ts)
export const MAX_PR_TITLE_LENGTH = 200;
export const MAX_PR_BODY_LENGTH = 10000;
export const MAX_PR_BRANCH_LENGTH = 100;
export const MAX_PR_REPO_LENGTH = 200;
export const MAX_PR_REPO_PATH_LENGTH = 200;
export const MAX_SUMMARY_LENGTH = 10000;
export const MAX_REPORT_CONTENT_LENGTH = 50000;

// --- Zod schemas (single source of truth) ---

export const PrConfigSchema = z.object({
  title: z.string().min(1).max(MAX_PR_TITLE_LENGTH).describe("PR 제목"),
  body: z.string().max(MAX_PR_BODY_LENGTH).describe("PR 설명 (마크다운)"),
  branch: z.string().min(1).max(MAX_PR_BRANCH_LENGTH).describe("소스 브랜치 이름"),
  base: z.string().max(MAX_PR_BRANCH_LENGTH).optional().default("main").describe("타겟 브랜치 (기본값: main)"),
  repo: z.string().min(1).max(MAX_PR_REPO_LENGTH).describe("GitHub 저장소 (owner/name 형식)"),
  repo_path: z.string().min(1).max(MAX_PR_REPO_PATH_LENGTH).describe("클론한 저장소의 /work 기준 상대 경로 (예: 'my-repo')"),
});

/** Extract required (non-optional) keys from a ZodObject schema. */
function requiredKeysOf<T extends z.ZodRawShape>(schema: z.ZodObject<T>): string[] {
  return Object.entries(schema.shape)
    .filter(([, v]) => !v.isOptional())
    .map(([k]) => k);
}

/**
 * Action → 조건부 필수 필드 매핑 (single source of truth).
 * - field: set_export_config 입력 스키마에서 검사할 top-level 필드명
 * - required_fields: get_export_actions 응답으로 에이전트에게 노출할 필드 경로
 */
export const ACTION_REQUIREMENTS: Record<string, { field: string; required_fields: string[] }> = {
  report: {
    field: "report_content",
    required_fields: ["report_content"],
  },
  create_pr: {
    field: "pr",
    required_fields: requiredKeysOf(PrConfigSchema).map((k) => `pr.${k}`),
  },
};

export const EXPORT_ACTIONS = [
  {
    type: "none" as const,
    description: "추가 작업 없음. 작업 요약 코멘트만 Linear 이슈에 추가됩니다.",
    required_fields: [] as string[],
  },
  {
    type: "upload_workspace" as const,
    description:
      "workspace 전체를 압축하여 Linear 이슈에 첨부합니다. 코드, 데이터, 결과물 등을 공유할 때 사용합니다.",
    required_fields: [] as string[],
  },
  {
    type: "report" as const,
    description:
      "분석 리포트를 Linear 이슈 코멘트로 추가합니다. 마크다운 형식의 상세 분석 결과를 공유할 때 사용합니다.",
    required_fields: ACTION_REQUIREMENTS.report.required_fields,
  },
  {
    type: "create_pr" as const,
    description:
      "GitHub Pull Request를 생성합니다. 코드 변경 사항을 리뷰 및 머지하기 위해 사용합니다.",
    required_fields: ACTION_REQUIREMENTS.create_pr.required_fields,
  },
  {
    type: "continue" as const,
    description:
      "현재 사이클을 종료하고 다음 사이클에서 에이전트 루프를 계속 진행합니다. 작업이 아직 완료되지 않았을 때 사용합니다.",
    required_fields: [] as string[],
  },
];
