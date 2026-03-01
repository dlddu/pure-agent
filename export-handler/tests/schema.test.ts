import { describe, it, expect } from "vitest";
import { ExportConfigSchema } from "../src/schema.js";

describe("ExportConfigSchema", () => {
  const minimal = { linear_issue_id: "TEAM-1", summary: "done", actions: ["none"] };

  it("parses valid minimal config", () => {
    expect(ExportConfigSchema.parse(minimal)).toMatchObject(minimal);
  });

  it("accepts all valid single action values", () => {
    const actionInputs: Record<string, Record<string, unknown>> = {
      none: {},
      upload_workspace: {},
      report: { report_content: "content" },
      create_pr: { pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" } },
      continue: {},
    };
    for (const [action, extra] of Object.entries(actionInputs)) {
      expect(() => ExportConfigSchema.parse({ ...minimal, actions: [action], ...extra })).not.toThrow();
    }
  });

  it("accepts multiple combinable actions", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["upload_workspace", "report"],
      report_content: "content",
    })).not.toThrow();
  });

  it("accepts all combinable actions together", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["upload_workspace", "report", "create_pr"],
      report_content: "content",
      pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" },
    })).not.toThrow();
  });

  it("rejects invalid action value", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, actions: ["invalid"] })).toThrow();
  });

  it("rejects empty actions array", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, actions: [] })).toThrow();
  });

  it("rejects duplicate actions", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["upload_workspace", "upload_workspace"],
    })).toThrow();
  });

  it("rejects none combined with other actions", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["none", "upload_workspace"],
    })).toThrow();
  });

  it("rejects continue combined with other actions", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["continue", "report"],
      report_content: "content",
    })).toThrow();
  });

  it("rejects upload_workspace without linear_issue_id", () => {
    const { linear_issue_id: _, ...rest } = minimal;
    expect(() => ExportConfigSchema.parse({ ...rest, actions: ["upload_workspace"] })).toThrow();
  });

  it("rejects report without linear_issue_id", () => {
    const { linear_issue_id: _, ...rest } = minimal;
    expect(() => ExportConfigSchema.parse({ ...rest, actions: ["report"], report_content: "content" })).toThrow();
  });

  it("accepts none without linear_issue_id", () => {
    const { linear_issue_id: _, ...rest } = minimal;
    expect(() => ExportConfigSchema.parse(rest)).not.toThrow();
  });

  it("accepts continue without linear_issue_id", () => {
    const { linear_issue_id: _, ...rest } = minimal;
    expect(() => ExportConfigSchema.parse({ ...rest, actions: ["continue"] })).not.toThrow();
  });

  it("accepts missing linear_issue_id", () => {
    const { linear_issue_id: _, ...rest } = minimal;
    const config = ExportConfigSchema.parse(rest);
    expect(config.linear_issue_id).toBeUndefined();
  });

  it("rejects empty linear_issue_id", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, linear_issue_id: "" })).toThrow();
  });

  it("rejects missing summary", () => {
    const { summary: _, ...rest } = minimal;
    expect(() => ExportConfigSchema.parse(rest)).toThrow();
  });

  it("rejects empty summary", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, summary: "" })).toThrow();
  });

  it("rejects summary exceeding max length", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, summary: "x".repeat(10001) })).toThrow();
  });

  it("accepts optional report_content", () => {
    const config = ExportConfigSchema.parse({ ...minimal, report_content: "report text" });
    expect(config.report_content).toBe("report text");
  });

  it("rejects report_content exceeding max length", () => {
    expect(() =>
      ExportConfigSchema.parse({ ...minimal, report_content: "x".repeat(50001) }),
    ).toThrow();
  });

  it("defaults pr.base to main when not provided", () => {
    const config = ExportConfigSchema.parse({
      ...minimal,
      actions: ["create_pr"],
      pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" },
    });
    expect(config.pr?.base).toBe("main");
  });

  it("accepts pr with all fields", () => {
    const config = ExportConfigSchema.parse({
      ...minimal,
      actions: ["create_pr"],
      pr: { title: "t", body: "b", branch: "feat/x", base: "develop", repo: "org/repo", repo_path: "repo" },
    });
    expect(config.pr?.base).toBe("develop");
    expect(config.pr?.repo).toBe("org/repo");
  });

  it("rejects pr.title exceeding max length", () => {
    expect(() =>
      ExportConfigSchema.parse({
        ...minimal,
        pr: { title: "x".repeat(201), body: "b", branch: "feat/x" },
      }),
    ).toThrow();
  });

  it("rejects pr with empty title", () => {
    expect(() =>
      ExportConfigSchema.parse({
        ...minimal,
        pr: { title: "", body: "b", branch: "feat/x" },
      }),
    ).toThrow();
  });

  it("rejects pr with empty branch", () => {
    expect(() =>
      ExportConfigSchema.parse({
        ...minimal,
        pr: { title: "t", body: "b", branch: "" },
      }),
    ).toThrow();
  });

  it("requires report_content when actions include report", () => {
    expect(() =>
      ExportConfigSchema.parse({ ...minimal, actions: ["report"] }),
    ).toThrow();
  });

  it("requires non-empty report_content when actions include report", () => {
    expect(() =>
      ExportConfigSchema.parse({ ...minimal, actions: ["report"], report_content: "" }),
    ).toThrow();
  });

  it("accepts report action with report_content", () => {
    const config = ExportConfigSchema.parse({
      ...minimal,
      actions: ["report"],
      report_content: "analysis result",
    });
    expect(config.report_content).toBe("analysis result");
  });

  it("requires pr config when actions include create_pr", () => {
    expect(() =>
      ExportConfigSchema.parse({ ...minimal, actions: ["create_pr"] }),
    ).toThrow();
  });

  it("accepts create_pr action with pr config", () => {
    const config = ExportConfigSchema.parse({
      ...minimal,
      actions: ["create_pr"],
      pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" },
    });
    expect(config.pr).toBeDefined();
  });
});
