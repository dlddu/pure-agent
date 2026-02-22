#!/bin/bash
# Shared test helpers for e2e/lib BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

LIB_DIR="$BATS_TEST_DIRNAME/.."

common_setup() {
  export WORK_DIR="$BATS_TEST_TMPDIR/work"
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$WORK_DIR" "$FIXTURE_DIR"
}

# Source assertions.sh in --source-only mode so we can call individual
# functions without triggering any top-level side effects.
load_assertions() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/assertions.sh" --source-only
}

# Source runner.sh in --source-only mode.
load_runner() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/runner.sh" --source-only
}
