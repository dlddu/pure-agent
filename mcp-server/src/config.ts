import { z } from "zod";

const ConfigSchema = z
  .object({
    PORT: z.coerce.number().default(8080),
    HOST: z.string().default("0.0.0.0"),
    MCP_PATH: z.string().default("/mcp"),
    WORK_DIR: z.string().default("/work"),
    LINEAR_API_KEY: z.string().min(1, "LINEAR_API_KEY is required"),
    LINEAR_TEAM_ID: z.string().min(1, "LINEAR_TEAM_ID is required"),
    LINEAR_DEFAULT_PROJECT_ID: z.string().optional(),
    LINEAR_DEFAULT_LABEL_ID: z.string().optional(),
    LINEAR_API_URL: z.string().optional(),
    GATEKEEPER_URL: z.string().optional(),
    GATEKEEPER_API_KEY: z.string().optional(),
    GATEKEEPER_POLL_INTERVAL_MS: z.coerce.number().default(3000),
    GATEKEEPER_TIMEOUT_MS: z.coerce.number().default(600000),
  })
  .superRefine((data, ctx) => {
    const hasUrl = data.GATEKEEPER_URL !== undefined && data.GATEKEEPER_URL !== "";
    const hasApiKey =
      data.GATEKEEPER_API_KEY !== undefined && data.GATEKEEPER_API_KEY !== "";

    if (hasApiKey && !hasUrl) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "GATEKEEPER_URL is required when GATEKEEPER_API_KEY is provided",
        path: ["GATEKEEPER_URL"],
      });
    }

    if (hasUrl && !hasApiKey) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "GATEKEEPER_API_KEY is required when GATEKEEPER_URL is provided",
        path: ["GATEKEEPER_API_KEY"],
      });
    }
  });

export type AppConfig = z.infer<typeof ConfigSchema>;

export function parseConfig(
  env: Record<string, string | undefined> = process.env,
): AppConfig {
  return Object.freeze(ConfigSchema.parse(env));
}
