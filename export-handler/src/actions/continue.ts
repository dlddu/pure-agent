import type { ActionHandler, ActionResult } from "./types.js";
import { createLogger } from "../logger.js";

const log = createLogger("action:continue");

export const continueHandler: ActionHandler = {
  validate(): void {},
  async execute(): Promise<ActionResult> {
    log.warn("Continue action reached export-handler. This should have been handled by the router.");
    return {};
  },
};
