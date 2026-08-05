import type { ExportAction } from "../constants.js";
import type { ActionHandler } from "./types.js";
import { noneHandler } from "./none.js";
import { createPrHandler } from "./create-pr.js";

export const actionRegistry: Record<ExportAction, ActionHandler> = {
  none: noneHandler,
  create_pr: createPrHandler,
};
