#!/usr/bin/env bats
# Tests for validate.sh, mcp-config.sh, prompt.sh

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants validate mcp-config prompt; }

# ── validate_env ─────────────────────────────────────────────

@test "validate_env: passes with both PROMPT and MCP_HOST set" {
  _load
  run validate_env
  [ "$status" -eq 0 ]
}

@test "validate_env: fails when PROMPT is missing" {
  _load
  unset PROMPT
  run validate_env
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROMPT"* ]]
}

@test "validate_env: fails when MCP_HOST is missing" {
  _load
  unset MCP_HOST
  run validate_env
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_HOST"* ]]
}

@test "validate_env: fails when both are missing" {
  _load
  unset PROMPT MCP_HOST
  run validate_env
  [ "$status" -eq 1 ]
  [[ "$output" == *"PROMPT"* ]]
  [[ "$output" == *"MCP_HOST"* ]]
}

# ── build_prompt ─────────────────────────────────────────────

@test "build_prompt: returns prompt when no previous output" {
  _load
  export PROMPT="Do the thing"
  unset PREVIOUS_OUTPUT
  result="$(build_prompt 2>/dev/null)"
  [ "$result" = "Do the thing" ]
}

@test "build_prompt: logs first cycle message" {
  _load
  export PROMPT="Do the thing"
  unset PREVIOUS_OUTPUT
  run build_prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"first cycle"* ]]
}

@test "build_prompt: includes previous output when present" {
  _load
  export PROMPT="Continue"
  export PREVIOUS_OUTPUT="Previous result"
  result="$(build_prompt 2>/dev/null)"
  [[ "$result" == *"Previous output:"* ]]
  [[ "$result" == *"Previous result"* ]]
  [[ "$result" == *"Continue with:"* ]]
  [[ "$result" == *"Continue"* ]]
}

@test "build_prompt: logs previous context size" {
  _load
  export PROMPT="Continue"
  export PREVIOUS_OUTPUT="Previous result"
  run build_prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous context"* ]]
}

@test "build_prompt: handles empty PREVIOUS_OUTPUT as first cycle" {
  _load
  export PROMPT="Start"
  export PREVIOUS_OUTPUT=""
  result="$(build_prompt 2>/dev/null)"
  [ "$result" = "Start" ]
}

@test "build_prompt: preserves special characters in prompt" {
  _load
  export PROMPT='Line1
Line2 "quoted"'
  unset PREVIOUS_OUTPUT
  result="$(build_prompt 2>/dev/null)"
  [[ "$result" == *"Line1"* ]]
  [[ "$result" == *"Line2"* ]]
  [[ "$result" == *'"quoted"'* ]]
}

# ── setup_mcp_config ─────────────────────────────────────────

@test "setup_mcp_config: writes valid JSON with custom port" {
  export MCP_HOST="my-server"
  export MCP_PORT="9090"
  _load
  run setup_mcp_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP config written"* ]]
  [[ "$output" == *"my-server:9090"* ]]
  jq -e . "$MCP_CONFIG" >/dev/null
  url=$(jq -r '.mcpServers["pure-agent"].url' "$MCP_CONFIG")
  [ "$url" = "http://my-server:9090/mcp" ]
}

@test "setup_mcp_config: uses default port 8080" {
  _load
  run setup_mcp_config
  [ "$status" -eq 0 ]
  url=$(jq -r '.mcpServers["pure-agent"].url' "$MCP_CONFIG")
  [ "$url" = "http://localhost:8080/mcp" ]
}

@test "setup_mcp_config: overwrites existing config" {
  _load
  echo '{"stale":"config"}' > "$MCP_CONFIG"
  run setup_mcp_config
  [ "$status" -eq 0 ]
  url=$(jq -r '.mcpServers["pure-agent"].url' "$MCP_CONFIG")
  [ "$url" = "http://localhost:8080/mcp" ]
  # Verify stale content is gone
  [ "$(jq -r '.stale // "absent"' "$MCP_CONFIG")" = "absent" ]
}

@test "setup_mcp_config: dies when target directory is not writable" {
  # MCP_CONFIG is readonly after _load, so run in a subshell with override
  run bash -c "
    export WORK_DIR='$WORK_DIR' MCP_HOST='$MCP_HOST' MCP_PORT='$MCP_PORT'
    export MCP_CONFIG='$BATS_TEST_TMPDIR/nonexistent-dir/mcp.json'
    source '$LIB_DIR/logging.sh'
    source '$LIB_DIR/mcp-config.sh'
    setup_mcp_config
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to write MCP config"* ]]
}
