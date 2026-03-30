"""MCP client configuration generation for planner."""

from __future__ import annotations

import json
import logging
import os

logger = logging.getLogger("planner")

DEFAULT_MCP_PORT = "8080"


def write_mcp_config(config_path: str, mcp_host: str, mcp_port: str | None = None) -> None:
    """Write MCP client configuration JSON for Claude Code CLI.

    Args:
        config_path: Path to write the MCP config file.
        mcp_host: Hostname of the MCP server.
        mcp_port: Port of the MCP server (default: 8080).
    """
    port = mcp_port or os.environ.get("MCP_PORT", DEFAULT_MCP_PORT)
    config = {
        "mcpServers": {
            "pure-agent": {
                "type": "http",
                "url": f"http://{mcp_host}:{port}/mcp",
            }
        }
    }
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    logger.info("MCP config written: %s (%s:%s)", config_path, mcp_host, port)


def get_mcp_config_path(base_dir: str = "/tmp") -> str:
    """Return the path for the planner MCP config file."""
    return os.path.join(base_dir, "planner_mcp.json")
