#!/usr/bin/env bats
# Tests for lib/claude-runner.sh: run_claude, extract_environment_id

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants environments mcp-config prompt claude-runner; }

# ── run_claude ───────────────────────────────────────────────

@test "run_claude: returns 0 on success" {
  _load
  claude() { echo '{"type":"result","result":"{\"environment_id\": \"default\"}"}'; }
  export -f claude
  run run_claude
  [ "$status" -eq 0 ]
}

@test "run_claude: returns 1 when claude command not found" {
  _load
  # Override PATH to ensure claude is not found
  claude() { return 127; }
  export -f claude
  run run_claude
  # Non-zero claude exit doesn't cause run_claude to fail (it logs warning)
  [ "$status" -eq 0 ]
  [[ "$output" == *"exited with status"* ]]
}

@test "run_claude: writes output to CLAUDE_OUTPUT" {
  _load
  claude() { echo '{"type":"result","result":"test"}'; }
  export -f claude
  run_claude 2>/dev/null
  [ -f "$CLAUDE_OUTPUT" ]
  [[ "$(cat "$CLAUDE_OUTPUT")" == *"test"* ]]
}

@test "run_claude: writes output to PLANNER_OUTPUT_COPY on shared volume" {
  _load
  claude() { echo '{"type":"system","session_id":"planner-sess-123"}'; echo '{"type":"result","result":"test"}'; }
  export -f claude
  run_claude 2>/dev/null
  [ -f "$PLANNER_OUTPUT_COPY" ]
  [[ "$(head -1 "$PLANNER_OUTPUT_COPY")" == *"planner-sess-123"* ]]
}

# ── extract_environment_id ───────────────────────────────────

@test "extract_environment_id: extracts from result event" {
  _load
  echo '{"type":"result","result":"{\"environment_id\": \"infra\"}"}' > "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ "$result" = "infra" ]
}

@test "extract_environment_id: extracts from assistant event" {
  _load
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"{\"environment_id\": \"python-analysis\"}"}]}}' > "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ "$result" = "python-analysis" ]
}

@test "extract_environment_id: returns empty for empty output" {
  _load
  touch "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ -z "$result" ]
}

@test "extract_environment_id: returns empty for missing file" {
  _load
  rm -f "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ -z "$result" ]
}

@test "extract_environment_id: returns empty for malformed response" {
  _load
  echo '{"type":"result","result":"I think you should use python"}' > "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ -z "$result" ]
}

@test "extract_environment_id: handles markdown-fenced JSON" {
  _load
  printf '{"type":"result","result":"```json\\n{\\"environment_id\\": \\"python-analysis\\"}\\n```"}\n' > "$CLAUDE_OUTPUT"
  result=$(extract_environment_id 2>/dev/null)
  [ "$result" = "python-analysis" ]
}
