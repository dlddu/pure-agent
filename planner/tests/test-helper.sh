#!/bin/bash
# Shared test helpers for planner BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

LIB_DIR="$BATS_TEST_DIRNAME/../lib"

# Common environment setup for all planner tests.
# Call this from each test file's setup() function.
common_setup() {
  export PROMPT="test prompt"
  export MCP_HOST=""
  export MCP_PORT="8080"
  export CLAUDE_OUTPUT="$BATS_TEST_TMPDIR/claude_output.json"
  export MCP_CONFIG="$BATS_TEST_TMPDIR/mcp.json"
  export EXTRACT_ENV_FILTER="$BATS_TEST_DIRNAME/../extract-environment.jq"
  export PLANNER_CLAUDE_MD=""
}

# Source specific lib modules by name.
# Each module is sourced in the order specified, so callers control
# the dependency chain.
# Usage: _load_lib logging constants environments
_load_lib() {
  set -eo pipefail  # match entrypoint.sh shell options
  for mod in "$@"; do
    # shellcheck disable=SC1090
    source "$LIB_DIR/$mod.sh"
  done
  set +u  # allow unset variables in tests
}

# Source the full entrypoint.sh (all modules + main).
# Used only by entrypoint.bats for integration tests.
_load_entrypoint() {
  source "$BATS_TEST_DIRNAME/../entrypoint.sh" --source-only
  set +u
}
