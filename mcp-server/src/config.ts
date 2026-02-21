import { z } from "zod";

const ConfigSchema = z.object({
  PORT: z.coerce.number().default(8080),
  HOST: z.string().default("0.0.0.0"),
  MCP_PATH: z.string().default("/mcp"),
  WORK_DIR: z.string().default("/work"),
  LINEAR_API_KEY: z.string().min(1, "LINEAR_API_KEY is required"),
  LINEAR_TEAM_ID: z.string().min(1, "LINEAR_TEAM_ID is required"),
  LINEAR_DEFAULT_PROJECT_ID: z.string().optional(),
  LINEAR_DEFAULT_LABEL_ID: z.string().optional(),
});

export type AppConfig = z.infer<typeof ConfigSchema>;

export function parseConfig(
  env: Record<string, string | undefined> = process.env,
): AppConfig {
  return Object.freeze(ConfigSchema.parse(env));
}
