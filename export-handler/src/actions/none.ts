import type { ActionHandler, ActionResult } from "./types.js";
import { createLogger } from "../logger.js";

const log = createLogger("action:none");

export const noneHandler: ActionHandler = {
  validate(): void {},
  async execute(): Promise<ActionResult> {
    log.info("Action: none. No additional work.");
    return {};
  },
};
