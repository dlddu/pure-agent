#!/usr/bin/env bats
# Tests for lib/claude-runner.sh: run_claude, extract_result

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants config claude-runner; }

# ── run_claude ───────────────────────────────────────────────

@test "run_claude: returns 0 on success" {
  _load
  claude() { echo '{"type":"result","result":"ok"}'; }
  export -f claude
  run run_claude
  [ "$status" -eq 0 ]
}

@test "run_claude: propagates non-zero exit code" {
  _load
  claude() { return 42; }
  export -f claude
  run run_claude
  [ "$status" -eq 42 ]
  [[ "$output" == *"exited with status 42"* ]]
}

@test "run_claude: writes output to both AGENT_OUTPUT and AGENT_OUTPUT_COPY" {
  _load
  claude() { echo '{"type":"result","result":"test"}'; }
  export -f claude
  run_claude 2>/dev/null
  [ -f "$AGENT_OUTPUT" ]
  [ -f "$AGENT_OUTPUT_COPY" ]
  [[ "$(cat "$AGENT_OUTPUT")" == *"test"* ]]
  [[ "$(cat "$AGENT_OUTPUT_COPY")" == *"test"* ]]
}

@test "run_claude: creates output files even with empty output" {
  _load
  claude() { true; }
  export -f claude
  run_claude 2>/dev/null
  [ -f "$AGENT_OUTPUT" ]
  [ -f "$AGENT_OUTPUT_COPY" ]
}

@test "run_claude: handles multi-line stream-json output" {
  _load
  claude() {
    printf '{"type":"system","data":"init"}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}\n'
    printf '{"type":"result","result":"Done"}\n'
  }
  export -f claude
  run_claude 2>/dev/null
  [ "$(wc -l < "$AGENT_OUTPUT")" -eq 3 ]
  [ "$(wc -l < "$AGENT_OUTPUT_COPY")" -eq 3 ]
}

# ── extract_result ───────────────────────────────────────────

@test "extract_result: falls back when agent output is empty" {
  _load
  touch "$AGENT_OUTPUT"
  run extract_result
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty or missing"* ]]
  [[ "$output" == *"Result extracted"* ]]
  [ "$(cat "$RESULT_FILE")" = "$FALLBACK_RESULT" ]
}

@test "extract_result: falls back when agent output does not exist" {
  _load
  rm -f "$AGENT_OUTPUT"
  run extract_result
  [ "$status" -eq 0 ]
  [ "$(cat "$RESULT_FILE")" = "No output captured" ]
}

@test "extract_result: extracts result from valid stream-json" {
  _load
  echo '{"type":"result","result":"Task completed"}' > "$AGENT_OUTPUT"
  run extract_result
  [ "$status" -eq 0 ]
  [[ "$output" == *"Result extracted"* ]]
  [ "$(cat "$RESULT_FILE")" = "Task completed" ]
}

@test "extract_result: falls back on malformed JSON" {
  _load
  echo 'this is not json' > "$AGENT_OUTPUT"
  run extract_result
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq extraction failed"* ]]
  [ "$(cat "$RESULT_FILE")" = "Output not parseable" ]
}

@test "extract_result: falls back when jq filter file is missing" {
  export EXTRACT_RESULT_FILTER="$BATS_TEST_TMPDIR/nonexistent.jq"
  _load
  echo '{"type":"result","result":"ok"}' > "$AGENT_OUTPUT"
  run extract_result
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq extraction failed"* ]]
  [ "$(cat "$RESULT_FILE")" = "Output not parseable" ]
}
