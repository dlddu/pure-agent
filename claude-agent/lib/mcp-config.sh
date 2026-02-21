#!/bin/bash
# MCP client configuration generation for claude-agent.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

# Generate MCP client configuration JSON at $MCP_CONFIG.
# Dies on write failure.
setup_mcp_config() {
  if ! cat > "$MCP_CONFIG" << EOF
{
  "mcpServers": {
    "pure-agent": {
      "type": "http",
      "url": "http://${MCP_HOST}:${MCP_PORT}/mcp"
    }
  }
}
EOF
  then
    die "Failed to write MCP config to $MCP_CONFIG"
  fi
  log "MCP config written (${MCP_HOST}:${MCP_PORT})"
}
