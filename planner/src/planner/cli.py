"""CLI entry point: argument parsing, orchestration, error handling."""

import argparse
import logging
import os
import sys

from planner.environments import resolve_image

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("planner")


def main() -> None:
    parser = argparse.ArgumentParser(description="Select agent execution environment")
    parser.add_argument("--prompt", type=str, required=True, help="Task prompt to analyze")
    parser.add_argument("--output", type=str, required=True, help="Output file for image")
    parser.add_argument(
        "--raw-id-output", type=str, default="", help="Output file for raw LLM environment ID"
    )

    args = parser.parse_args()

    mcp_config_path = _setup_mcp_config()
    claude_md_path = os.environ.get("PLANNER_CLAUDE_MD", "")

    from planner.image_selector import select_image_via_llm

    image, raw_id = select_image_via_llm(
        args.prompt,
        mcp_config_path=mcp_config_path,
        claude_md_path=claude_md_path or None,
    )
    logger.info("LLM selected -> %s (raw_id=%s)", image, raw_id)

    _write_output(image, args.output)
    if args.raw_id_output:
        _write_output(raw_id or "", args.raw_id_output)


def _setup_mcp_config() -> str | None:
    """Create MCP config if MCP_HOST is set. Returns config path or None."""
    mcp_host = os.environ.get("MCP_HOST", "")
    if not mcp_host:
        logger.info("MCP_HOST not set, skipping MCP config (no tool access)")
        return None

    from planner.mcp_config import get_mcp_config_path, write_mcp_config

    config_path = get_mcp_config_path()
    write_mcp_config(config_path, mcp_host)
    return config_path


def _write_output(value: str, output_path: str) -> None:
    """Write the selected image to the output file."""
    with open(output_path, "w") as f:
        f.write(value + "\n")
    logger.info("Output: %s -> %s", value, output_path)


def _write_fallback_output() -> None:
    """Extract --output from sys.argv and write default image as fallback."""
    try:
        idx = sys.argv.index("--output")
        output_path = sys.argv[idx + 1]
        default_image = resolve_image(None)
        with open(output_path, "w") as f:
            f.write(default_image + "\n")
        logger.info("Wrote fallback output: %s -> %s", default_image, output_path)
    except (ValueError, IndexError, OSError):
        pass


def run() -> None:
    """Entry point with error handling. Always produces output."""
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        logger.exception("Planner crashed with unhandled exception")
        _write_fallback_output()
        sys.exit(1)
