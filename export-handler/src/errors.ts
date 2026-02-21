export function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function wrapError(error: unknown, context: string): Error {
  return new Error(`${context}: ${getErrorMessage(error)}`, { cause: error });
}

/**
 * Asserts a condition guaranteed by prior validate() call.
 * Provides TypeScript type narrowing in execute() methods.
 */
export function assertValidated(
  condition: unknown,
  field: string,
): asserts condition {
  if (!condition) {
    throw new Error(`Bug: ${field} missing — validate() should have been called first`);
  }
}
