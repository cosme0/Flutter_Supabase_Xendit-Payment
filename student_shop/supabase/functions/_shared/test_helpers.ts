/**
 * Tiny assertion helpers for the edge function tests.
 *
 * They are implemented locally (instead of using `jsr:@std/assert`) so that
 * `deno test` works without downloading anything.
 */

export class AssertionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AssertionError";
  }
}

/** Fails the test when the condition is not truthy. */
export function assert(condition: unknown, message = "assertion failed"): void {
  if (!condition) {
    throw new AssertionError(message);
  }
}

/**
 * Fails the test when the two values are not equal.
 * Primitives are compared strictly, objects and arrays by their content.
 */
export function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const isObject = typeof actual === "object" && actual !== null &&
    typeof expected === "object" && expected !== null;
  const equal = Object.is(actual, expected) ||
    (isObject && JSON.stringify(actual) === JSON.stringify(expected));

  if (!equal) {
    throw new AssertionError(
      message ?? `expected ${JSON.stringify(expected)} but got ${JSON.stringify(actual)}`,
    );
  }
}

/** Fails the test when the condition is truthy. */
export function assertFalse(condition: unknown, message = "expected a falsy value"): void {
  if (condition) {
    throw new AssertionError(message);
  }
}

/** Fails the test when the function does not throw. */
export function assertThrows(fn: () => unknown, message = "expected the function to throw"): void {
  try {
    fn();
  } catch {
    return;
  }
  throw new AssertionError(message);
}

/** Fails the test when the promise does not reject. */
export async function assertRejects(
  fn: () => Promise<unknown>,
  check?: (error: unknown) => boolean,
  message = "expected the promise to reject",
): Promise<void> {
  try {
    await fn();
  } catch (error) {
    if (check && !check(error)) {
      throw new AssertionError("the rejection did not match the expectation");
    }
    return;
  }
  throw new AssertionError(message);
}

/** The result type used by the validation helpers. */
export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; code: string; message: string };

/** Returns the value of a successful result, fails the test otherwise. */
export function expectOk<T>(result: Result<T>): T {
  if (!result.ok) {
    throw new AssertionError(`expected a successful result but got ${result.code}`);
  }
  return result.value;
}

/** Returns the error of a failed result, fails the test otherwise. */
export function expectError<T>(result: Result<T>): { code: string; message: string } {
  if (result.ok) {
    throw new AssertionError("expected a failed result but the result was successful");
  }
  return { code: result.code, message: result.message };
}
