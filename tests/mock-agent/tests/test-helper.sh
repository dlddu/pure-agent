#!/bin/bash
# Shared test helpers for mock-agent BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

MOCK_AGENT_DIR="$BATS_TEST_DIRNAME/.."

common_setup() {
  export WORK_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK_DIR"

  # Default SCENARIO_DIR points to a temp dir the test can populate
  export SCENARIO_DIR="$BATS_TEST_TMPDIR/scenario"
  mkdir -p "$SCENARIO_DIR"
}

# Run the entrypoint script in a controlled environment.
# All required env vars must be set before calling this.
run_entrypoint() {
  bash "$MOCK_AGENT_DIR/entrypoint.sh"
}
