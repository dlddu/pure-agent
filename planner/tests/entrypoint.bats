#!/usr/bin/env bats
# Integration tests for entrypoint.sh main() function

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  TEST_OUTPUT="$BATS_TEST_TMPDIR/agent_image.txt"
  TEST_RAW_OUTPUT="$BATS_TEST_TMPDIR/raw_environment_id.txt"
}

_load() { _load_entrypoint; }

# ── argument parsing ────────────────────────────────────────

@test "parse_args: parses --prompt and --output" {
  _load
  parse_args --prompt "hello" --output "/tmp/out.txt"
  [ "$PROMPT" = "hello" ]
  [ "$OUTPUT" = "/tmp/out.txt" ]
}

@test "parse_args: parses --raw-id-output" {
  _load
  parse_args --prompt "hello" --output "/tmp/out.txt" --raw-id-output "/tmp/raw.txt"
  [ "$RAW_ID_OUTPUT" = "/tmp/raw.txt" ]
}

@test "main: fails when --output is missing" {
  _load
  run main --prompt "task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--output is required"* ]]
}

@test "main: fails when PROMPT is missing" {
  _load
  PROMPT=""
  run main --output "$TEST_OUTPUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

# ── main (integration) ──────────────────────────────────────

@test "main: selects default environment" {
  _load
  claude() {
    echo '{"type":"result","result":"{\"environment_id\": \"default\"}"}'
  }
  export -f claude
  run main --prompt "code review" --output "$TEST_OUTPUT" --raw-id-output "$TEST_RAW_OUTPUT"
  [ "$status" -eq 0 ]
  image=$(cat "$TEST_OUTPUT")
  [[ "$image" == *"claude-agent"* ]]
  raw_id=$(cat "$TEST_RAW_OUTPUT")
  [ "$raw_id" = "default" ]
}

@test "main: selects python-analysis environment" {
  _load
  claude() {
    echo '{"type":"result","result":"{\"environment_id\": \"python-analysis\"}"}'
  }
  export -f claude
  run main --prompt "pandas data analysis" --output "$TEST_OUTPUT" --raw-id-output "$TEST_RAW_OUTPUT"
  [ "$status" -eq 0 ]
  image=$(cat "$TEST_OUTPUT")
  [[ "$image" == *"python-agent"* ]]
}

@test "main: selects infra environment" {
  _load
  claude() {
    echo '{"type":"result","result":"{\"environment_id\": \"infra\"}"}'
  }
  export -f claude
  run main --prompt "kubectl deploy" --output "$TEST_OUTPUT" --raw-id-output "$TEST_RAW_OUTPUT"
  [ "$status" -eq 0 ]
  image=$(cat "$TEST_OUTPUT")
  [[ "$image" == *"infra-agent"* ]]
}

@test "main: falls back to default when claude output is empty" {
  _load
  claude() { true; }
  export -f claude
  run main --prompt "task" --output "$TEST_OUTPUT" --raw-id-output "$TEST_RAW_OUTPUT"
  [ "$status" -eq 0 ]
  image=$(cat "$TEST_OUTPUT")
  [[ "$image" == *"claude-agent"* ]]
  raw_id=$(cat "$TEST_RAW_OUTPUT")
  [ "$raw_id" = "_PARSE_EMPTY" ]
}

@test "main: falls back when unknown environment returned" {
  _load
  claude() {
    echo '{"type":"result","result":"{\"environment_id\": \"unknown-env\"}"}'
  }
  export -f claude
  run main --prompt "task" --output "$TEST_OUTPUT" --raw-id-output "$TEST_RAW_OUTPUT"
  [ "$status" -eq 0 ]
  image=$(cat "$TEST_OUTPUT")
  [[ "$image" == *"claude-agent"* ]]
}

@test "main: generates MCP config when MCP_HOST set" {
  _load
  export MCP_HOST="mcp-server"
  claude() {
    echo '{"type":"result","result":"{\"environment_id\": \"default\"}"}'
  }
  export -f claude
  run main --prompt "task" --output "$TEST_OUTPUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP config written"* ]]
}
