import type { ExportConfig } from "../schema.js";

export interface ActionDeps {
  workDir: string;
  githubToken?: string;
}

export interface ActionContext extends ActionDeps {
  config: ExportConfig;
}

export type ActionResult = Record<string, string>;

export interface ActionHandler {
  validate(context: ActionContext): void;
  execute(context: ActionContext): Promise<ActionResult>;
}
