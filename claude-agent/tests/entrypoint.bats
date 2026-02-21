#!/usr/bin/env bats
# Integration tests for entrypoint.sh main() function

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_entrypoint; }

# ── main (integration) ──────────────────────────────────────

@test "main: fails when WORK_DIR does not exist" {
  export WORK_DIR="$BATS_TEST_TMPDIR/nonexistent"
  _load
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "main: fails when EXTRACT_RESULT_FILTER is missing" {
  export EXTRACT_RESULT_FILTER="$BATS_TEST_TMPDIR/nonexistent.jq"
  _load
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing jq filter"* ]]
}

@test "main: warns when CLAUDE.md copy fails" {
  export CLAUDE_MD_SOURCE="$BATS_TEST_TMPDIR/nonexistent-claude.md"
  _load
  claude() { echo '{"type":"result","result":"ok"}'; }
  export -f claude
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to copy CLAUDE.md"* ]]
}

@test "main: succeeds with valid environment" {
  _load
  claude() { echo '{"type":"result","result":"done"}'; }
  export -f claude
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting claude-agent"* ]]
  [[ "$output" == *"Done"* ]]
}

@test "main: propagates claude exit code" {
  _load
  claude() { return 1; }
  export -f claude
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"completed with errors"* ]]
}

@test "cleanup: removes AGENT_OUTPUT but not contract files" {
  _load
  # Simulate post-main state: all output files exist
  echo "agent-output" > "$AGENT_OUTPUT"
  echo "agent-copy" > "$AGENT_OUTPUT_COPY"
  echo "result" > "$RESULT_FILE"
  cleanup
  [ ! -f "$AGENT_OUTPUT" ]
  [ -f "$AGENT_OUTPUT_COPY" ]
  [ -f "$RESULT_FILE" ]
}
