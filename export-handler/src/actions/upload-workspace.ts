import type { ActionHandler, ActionContext, ActionResult } from "./types.js";
import { createWorkspaceZip, uploadToLinear } from "../services/workspace-zip.js";
import { postLinearComment } from "../services/linear-comment.js";
import { workspaceUploadComment } from "../templates.js";
import { createLogger } from "../logger.js";

const log = createLogger("action:upload-workspace");

export const uploadWorkspaceHandler: ActionHandler = {
  validate({ issueId }: ActionContext): void {
    if (!issueId || issueId === "none") {
      throw new Error("upload_workspace action requires a valid Linear issue (linear_issue_id must be set)");
    }
  },
  async execute(context: ActionContext): Promise<ActionResult> {
    const { linearClient, issueId, workDir, zipOutputPath } = context;
    const filename = `workspace-${Date.now()}.zip`;

    log.info("Action: upload_workspace. Zipping and uploading...");

    const { zipBuffer, zipSizeBytes } = createWorkspaceZip(workDir, zipOutputPath);
    log.info(`Workspace zip created: ${(zipSizeBytes / 1024 / 1024).toFixed(2)} MB`);

    const assetUrl = await uploadToLinear({ linearClient, zipBuffer, zipSizeBytes, filename });

    await postLinearComment(linearClient, issueId!, workspaceUploadComment(filename, assetUrl), "upload");

    log.info("Workspace uploaded");

    return { asset_url: assetUrl };
  },
};
