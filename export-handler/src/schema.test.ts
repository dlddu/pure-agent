import { describe, it, expect } from "vitest";
import { ExportConfigSchema } from "./schema.js";

describe("ExportConfigSchema", () => {
  const minimal = { summary: "done", actions: ["none"] };

  it("parses valid minimal config", () => {
    expect(ExportConfigSchema.parse(minimal)).toMatchObject(minimal);
  });

  it("accepts all valid single action values", () => {
    const actionInputs: Record<string, Record<string, unknown>> = {
      none: {},
      create_pr: { pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" } },
    };
    for (const [action, extra] of Object.entries(actionInputs)) {
      expect(() => ExportConfigSchema.parse({ ...minimal, actions: [action], ...extra })).not.toThrow();
    }
  });

  it("rejects removed action values (upload_workspace, report)", () => {
    expect(() => ExportConfigSchema.parse({ ...minimal, actions: ["upload_workspace"] })).toThrow();
    expect(() => ExportConfigSchema.parse({ ...minimal, actions: ["report"] })).toThrow();
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
      actions: ["create_pr", "create_pr"],
      pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" },
    })).toThrow();
  });

  it("rejects none combined with other actions", () => {
    expect(() => ExportConfigSchema.parse({
      ...minimal,
      actions: ["none", "create_pr"],
      pr: { title: "t", body: "b", branch: "feat/x", repo: "org/repo", repo_path: "repo" },
    })).toThrow();
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
