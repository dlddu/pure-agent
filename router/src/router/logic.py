"""Core routing logic: decision functions and file operations."""

import json
import logging
import os

from router.config import RouterConfig

logger = logging.getLogger("router")


def should_continue(
    config: RouterConfig, export_config_json: str, depth: int, max_depth: int
) -> tuple[bool, str, str | None]:
    """Decide whether the agent loop should continue.

    Args:
        config: Router configuration (file paths).
        export_config_json: JSON string from the agent's export_config output.
        depth: Current iteration depth (0-indexed).
        max_depth: Maximum allowed iterations.

    Returns (continue, reason, next_environment_id).
        next_environment_id is extracted from export_config if present, else None.
    """
    try:
        export_data = json.loads(export_config_json) if export_config_json.strip() else {}
    except json.JSONDecodeError as exc:
        logger.warning("Failed to parse export_config JSON: %s", exc)
        return False, "export_config provided (unparseable)", None

    next_environment: str | None = export_data.get("next_environment") if export_data else None

    if export_data:
        actions = export_data.get("actions", [])

        if "continue" in actions:
            # Delete the file so the next iteration starts fresh
            try:
                os.remove(config.export_config)
                logger.info("Deleted export_config.json for continue action")
            except OSError as exc:
                logger.warning("Could not delete export_config.json: %s", exc)
            return True, "continue action requested", next_environment

        return False, "export_config provided", next_environment

    # depth is 0-indexed; the agent has already run at this depth.
    # Stop when this is the last allowed iteration (depth == max_depth - 1).
    if depth >= max_depth - 1:
        return False, f"depth limit ({depth}/{max_depth})", None
    return True, "no export_config, continuing", None


def write_output(value: str, output_path: str) -> None:
    """Write the decision value to the output file."""
    with open(output_path, "w") as f:
        f.write(value + "\n")
    logger.info("Output: %s -> %s", value, output_path)
