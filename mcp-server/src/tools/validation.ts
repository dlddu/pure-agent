/**
 * Validates that a Git URL is safe for shell execution.
 * Returns an error message string, or null if valid.
 */
export function validateGitUrl(url: string): string | null {
  if (url.startsWith("-")) {
    return "Repository URL must not start with a dash";
  }
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(url)) {
    return "Repository URL contains invalid control characters";
  }
  return null;
}

/**
 * Validates that a directory name is safe (no traversal, no injection).
 * Returns an error message string, or null if valid.
 */
export function validateDirectoryName(dir: string): string | null {
  if (dir === "." || dir === "..") {
    return "Directory name must not be '.' or '..'";
  }
  if (dir.includes("/") || dir.includes("\\")) {
    return "Directory name must not contain path separators";
  }
  if (dir.startsWith("-")) {
    return "Directory name must not start with a dash";
  }
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(dir)) {
    return "Directory name contains invalid control characters";
  }
  return null;
}
