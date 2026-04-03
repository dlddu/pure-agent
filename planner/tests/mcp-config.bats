#!/usr/bin/env bats
# Tests for lib/mcp-config.sh: setup_mcp_config

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants mcp-config; }

# ── setup_mcp_config ─────────────────────────────────────────

@test "setup_mcp_config: skips when MCP_HOST is empty" {
  export MCP_HOST=""
  _load
  run setup_mcp_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping MCP config"* ]]
  [ "$HAS_MCP_CONFIG" -eq 0 ]
}

@test "setup_mcp_config: writes valid JSON when MCP_HOST set" {
  export MCP_HOST="mcp-server"
  _load
  setup_mcp_config 2>/dev/null
  [ -f "$MCP_CONFIG" ]
  jq -e '.mcpServers."pure-agent"' "$MCP_CONFIG" >/dev/null
}

@test "setup_mcp_config: uses default port 8080" {
  export MCP_HOST="mcp-host"
  export MCP_PORT="8080"
  _load
  setup_mcp_config 2>/dev/null
  url=$(jq -r '.mcpServers."pure-agent".url' "$MCP_CONFIG")
  [[ "$url" == *"8080"* ]]
}

@test "setup_mcp_config: uses custom port" {
  export MCP_HOST="mcp-host"
  export MCP_PORT="9090"
  _load
  setup_mcp_config 2>/dev/null
  url=$(jq -r '.mcpServers."pure-agent".url' "$MCP_CONFIG")
  [[ "$url" == *"9090"* ]]
}

@test "setup_mcp_config: url format is correct" {
  export MCP_HOST="my-host"
  export MCP_PORT="8080"
  _load
  setup_mcp_config 2>/dev/null
  url=$(jq -r '.mcpServers."pure-agent".url' "$MCP_CONFIG")
  [ "$url" = "http://my-host:8080/mcp" ]
}

@test "setup_mcp_config: sets HAS_MCP_CONFIG=1" {
  export MCP_HOST="mcp-server"
  _load
  setup_mcp_config 2>/dev/null
  [ "$HAS_MCP_CONFIG" -eq 1 ]
}

@test "setup_mcp_config: type is http" {
  export MCP_HOST="mcp-server"
  _load
  setup_mcp_config 2>/dev/null
  type=$(jq -r '.mcpServers."pure-agent".type' "$MCP_CONFIG")
  [ "$type" = "http" ]
}
