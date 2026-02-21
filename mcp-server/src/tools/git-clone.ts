import { z } from "zod";
import { join, basename } from "node:path";
import { defineTool, mcpSuccess, mcpError } from "./tool-utils.js";

const CLONE_TIMEOUT_MS = 300_000; // 5 minutes

// eslint-disable-next-line no-control-regex
const CONTROL_CHARS_RE = /[\x00-\x1f\x7f]/;

const GitCloneInputSchema = z.object({
  url: z
    .string()
    .min(1, "Repository URL is required")
    .refine((url) => !url.startsWith("-"), "Repository URL must not start with a dash")
    .refine((url) => !CONTROL_CHARS_RE.test(url), "Repository URL contains invalid control characters")
    .describe("Git repository URL (HTTPS or SSH format)"),
  branch: z
    .string()
    .max(256, "Branch name must be at most 256 characters")
    .optional()
    .describe("Branch to checkout after cloning. If omitted, uses the repository's default branch."),
  directory: z
    .string()
    .max(256, "Directory name must be at most 256 characters")
    .refine((d) => d !== "." && d !== "..", "Directory name must not be '.' or '..'")
    .refine((d) => !d.includes("/") && !d.includes("\\"), "Directory name must not contain path separators")
    .refine((d) => !d.startsWith("-"), "Directory name must not start with a dash")
    .refine((d) => !CONTROL_CHARS_RE.test(d), "Directory name contains invalid control characters")
    .optional()
    .describe("Target directory name within the working directory. If omitted, inferred from the repository URL."),
});

function inferDirectoryFromUrl(url: string): string {
  const cleaned = url.replace(/\/+$/, "").replace(/\.git$/, "");
  return basename(cleaned);
}

export const gitCloneTool = defineTool({
  name: "git_clone",
  description:
    "Git 저장소를 작업 디렉토리에 클론합니다. 원격 저장소의 소스 코드를 분석, 수정, 참고용으로 다운로드할 때 사용합니다.",
  schema: GitCloneInputSchema,
  handler: async (args, context) => {
    const { workDir } = context;

    const dirName = args.directory ?? inferDirectoryFromUrl(args.url);
    const clonePath = join(workDir, dirName);

    try {
      await context.fs.access(clonePath);
      return mcpError(`Directory already exists: ${dirName}`);
    } catch {
      // Path does not exist — proceed
    }

    const gitArgs = ["clone", "--progress"];
    if (args.branch) {
      gitArgs.push("--branch", args.branch);
    }
    gitArgs.push(args.url, dirName);

    context.logger.info(`Cloning ${args.url} into ${clonePath}`);
    await context.exec.execFile("git", gitArgs, { cwd: workDir, timeout: CLONE_TIMEOUT_MS, maxBuffer: 10 * 1024 * 1024 });

    return mcpSuccess({
      success: true,
      message: "Repository cloned successfully",
      path: clonePath,
      url: args.url,
      branch: args.branch ?? "default",
    });
  },
});
