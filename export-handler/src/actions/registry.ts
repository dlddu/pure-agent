import type { ExportAction } from "../constants.js";
import type { ActionHandler } from "./types.js";
import { noneHandler } from "./none.js";
import { uploadWorkspaceHandler } from "./upload-workspace.js";
import { reportHandler } from "./report.js";
import { createPrHandler } from "./create-pr.js";
import { continueHandler } from "./continue.js";

export const actionRegistry: Record<ExportAction, ActionHandler> = {
  none: noneHandler,
  upload_workspace: uploadWorkspaceHandler,
  report: reportHandler,
  create_pr: createPrHandler,
  continue: continueHandler,
};
