export const ACTION_NONE = "none" as const;
export const ACTION_UPLOAD_WORKSPACE = "upload_workspace" as const;
export const ACTION_REPORT = "report" as const;
export const ACTION_CREATE_PR = "create_pr" as const;
export const ACTION_CONTINUE = "continue" as const;

export const EXPORT_ACTIONS = [
  ACTION_NONE,
  ACTION_UPLOAD_WORKSPACE,
  ACTION_REPORT,
  ACTION_CREATE_PR,
  ACTION_CONTINUE,
] as const;

export type ExportAction = (typeof EXPORT_ACTIONS)[number];

/** Actions that must be the sole element when present in the actions array. */
export const EXCLUSIVE_ACTIONS: ReadonlySet<ExportAction> = new Set([
  ACTION_NONE,
  ACTION_CONTINUE,
]);

/** Actions that require a valid linear_issue_id. */
export const ACTIONS_REQUIRING_ISSUE: ReadonlySet<ExportAction> = new Set([
  ACTION_UPLOAD_WORKSPACE,
  ACTION_REPORT,
]);

export const DEFAULT_WORK_DIR = "/work";
export const DEFAULT_TMP_DIR = "/tmp";

export const EXPORT_CONFIG_FILENAME = "export_config.json";
export const ACTION_RESULTS_FILENAME = "action_results.json";
export const WORKSPACE_ZIP_FILENAME = "workspace.zip";

export const ZIP_EXCLUDE_PATTERNS = [
  ".git/*",
  "node_modules/*",
  EXPORT_CONFIG_FILENAME,
] as const;

// Validation limits for export config fields
export const MAX_PR_TITLE_LENGTH = 200;
export const MAX_PR_BODY_LENGTH = 10000;
export const MAX_PR_BRANCH_LENGTH = 100;
export const MAX_PR_REPO_LENGTH = 200;
export const MAX_PR_REPO_PATH_LENGTH = 200;
export const MAX_SUMMARY_LENGTH = 10000;
export const MAX_REPORT_CONTENT_LENGTH = 50000;
