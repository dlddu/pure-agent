#!/bin/bash
# Shared test helpers for mock-gh BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

MOCK_GH_DIR="$BATS_TEST_DIRNAME/.."

common_setup() {
  # Directory where mock-gh writes call records
  export GH_CALLS_DIR="$BATS_TEST_TMPDIR/gh-calls"
  mkdir -p "$GH_CALLS_DIR"
}

# Invoke the mock gh script with the given arguments.
# The GH_CALLS_DIR env var controls where call records are written.
run_mock_gh() {
  "$MOCK_GH_DIR/gh" "$@"
}
