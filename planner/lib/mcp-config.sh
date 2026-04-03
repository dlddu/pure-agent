#!/bin/bash
# MCP client configuration generation for planner.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

# Generate MCP client configuration JSON at $MCP_CONFIG.
# Only generates if MCP_HOST is set. Returns 0 always.
# Sets HAS_MCP_CONFIG=1 if config was created.
# shellcheck disable=SC2034
HAS_MCP_CONFIG=0
setup_mcp_config() {
  local mcp_host="${MCP_HOST:-}"
  if [ -z "$mcp_host" ]; then
    log "MCP_HOST not set, skipping MCP config (no tool access)"
    return 0
  fi

  if ! cat > "$MCP_CONFIG" << EOF
{
  "mcpServers": {
    "pure-agent": {
      "type": "http",
      "url": "http://${mcp_host}:${MCP_PORT}/mcp"
    }
  }
}
EOF
  then
    warn "Failed to write MCP config to $MCP_CONFIG"
    return 0
  fi
  # shellcheck disable=SC2034
  HAS_MCP_CONFIG=1
  log "MCP config written (${mcp_host}:${MCP_PORT})"
}
