import { describe, it, expect } from "vitest";
import { validateGitUrl, validateDirectoryName } from "../../src/tools/validation.js";

describe("validateGitUrl", () => {
  it("returns null for a valid HTTPS URL", () => {
    expect(validateGitUrl("https://github.com/org/repo.git")).toBeNull();
  });

  it("returns null for a valid SSH URL", () => {
    expect(validateGitUrl("git@github.com:org/repo.git")).toBeNull();
  });

  it("returns error for URL starting with a dash", () => {
    expect(validateGitUrl("--upload-pack=evil")).toBe(
      "Repository URL must not start with a dash",
    );
  });

  it("returns error for URL containing null byte", () => {
    expect(validateGitUrl("https://example.com/repo\x00.git")).toBe(
      "Repository URL contains invalid control characters",
    );
  });

  it("returns error for URL containing other control characters", () => {
    expect(validateGitUrl("https://example.com/repo\x1f")).toBe(
      "Repository URL contains invalid control characters",
    );
  });
});

describe("validateDirectoryName", () => {
  it("returns null for a valid directory name", () => {
    expect(validateDirectoryName("my-project")).toBeNull();
  });

  it("returns error for '.'", () => {
    expect(validateDirectoryName(".")).toBe("Directory name must not be '.' or '..'");
  });

  it("returns error for '..'", () => {
    expect(validateDirectoryName("..")).toBe("Directory name must not be '.' or '..'");
  });

  it("returns error for name containing forward slash", () => {
    expect(validateDirectoryName("../etc")).toBe(
      "Directory name must not contain path separators",
    );
  });

  it("returns error for name containing backslash", () => {
    expect(validateDirectoryName("dir\\sub")).toBe(
      "Directory name must not contain path separators",
    );
  });

  it("returns error for name starting with a dash", () => {
    expect(validateDirectoryName("-malicious")).toBe(
      "Directory name must not start with a dash",
    );
  });

  it("returns error for name containing control characters", () => {
    expect(validateDirectoryName("dir\x00name")).toBe(
      "Directory name contains invalid control characters",
    );
  });
});
