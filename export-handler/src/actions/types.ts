import type { LinearClient } from "@linear/sdk";
import type { ExportConfig } from "../schema.js";

export interface ActionDeps {
  workDir: string;
  zipOutputPath: string;
  githubToken?: string;
}

export interface ActionContext extends ActionDeps {
  linearClient: LinearClient;
  issueId: string | undefined;
  config: ExportConfig;
}

export type ActionResult = Record<string, string>;

export interface ActionHandler {
  validate(context: ActionContext): void;
  execute(context: ActionContext): Promise<ActionResult>;
}
