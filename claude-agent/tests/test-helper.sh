#!/bin/bash
# Shared test helpers for claude-agent BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

LIB_DIR="$BATS_TEST_DIRNAME/../lib"
HOOKS_DIR="$BATS_TEST_DIRNAME/../hooks"

# Common environment setup for all claude-agent tests.
# Call this from each test file's setup() function.
common_setup() {
  export WORK_DIR="$BATS_TEST_TMPDIR/work"
  export CLAUDE_DIR="$BATS_TEST_TMPDIR/.claude"
  export MCP_HOST="localhost"
  export MCP_PORT="8080"
  export PROMPT="test prompt"
  mkdir -p "$WORK_DIR" "$CLAUDE_DIR"

  cp "$BATS_TEST_DIRNAME/../extract-result.jq" "$BATS_TEST_TMPDIR/extract-result.jq"
  export EXTRACT_RESULT_FILTER="$BATS_TEST_TMPDIR/extract-result.jq"
  export AGENT_OUTPUT="$BATS_TEST_TMPDIR/agent_output.json"
  export RESULT_FILE="$BATS_TEST_TMPDIR/agent_result.txt"
  export SESSION_ID_FILE="$BATS_TEST_TMPDIR/session_id.txt"
}

# Source specific lib modules by name.
# Each module is sourced in the order specified, so callers control
# the dependency chain.
# Usage: _load_lib logging constants config
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

# Run bash code in a subshell with hooks/lib.sh sourced.
# Hooks call exit directly, so they must run in an isolated process.
# Caller's stdin is forwarded to the subshell.
# Usage: run _run_hook_lib "hook_block 'message'"
_run_hook_lib() {
  local code="$1"
  bash -c "
    export WORK_DIR='$WORK_DIR'
    source '$HOOKS_DIR/lib.sh'
    $code
  "
}

# Run a hook script with WORK_DIR exported and optional JSON piped to stdin.
# $1 = script filename (relative to HOOKS_DIR)
# $2 = (optional) stop_hook_active value: "true", "false", or omitted for empty stdin
# Usage: run _run_hook_script ensure-export-config.sh false
_run_hook_script() {
  local script="$1"
  local bypass="${2:-}"
  local input=""
  if [ -n "$bypass" ]; then
    input="{\"stop_hook_active\":$bypass}"
  fi
  bash -c "
    export WORK_DIR='$WORK_DIR'
    echo '$input' | '$HOOKS_DIR/$script'
  "
}
