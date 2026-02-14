#!/usr/bin/env python3
"""File-based router: decides continue/stop based on export_config.json presence."""

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone

EXPORT_CONFIG = "/work/export_config.json"
STATE_PATH = "/work/state.json"

logging.basicConfig(
    stream=sys.stderr,
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("router")


def load_state():
    if os.path.exists(STATE_PATH):
        try:
            size = os.path.getsize(STATE_PATH)
            logger.debug("State file %s exists (%d bytes)", STATE_PATH, size)
            with open(STATE_PATH) as f:
                state = json.load(f)
            logger.debug("State loaded successfully: %d history entries", len(state.get("history", [])))
            return state
        except (json.JSONDecodeError, IOError) as e:
            logger.warning("Failed to parse state file %s: %s, starting fresh", STATE_PATH, e)
    else:
        logger.debug("State file %s does not exist, starting fresh", STATE_PATH)
    return {"history": []}


def save_state(state):
    try:
        with open(STATE_PATH, "w") as f:
            json.dump(state, f, indent=2)
        logger.debug("State saved to %s (%d bytes)", STATE_PATH, os.path.getsize(STATE_PATH))
    except IOError as e:
        logger.error("Failed to save state to %s: %s", STATE_PATH, e)
        raise


def main():
    parser = argparse.ArgumentParser(description="Workflow router")
    parser.add_argument("--depth", type=int, required=True)
    parser.add_argument("--max-depth", type=int, required=True)
    args = parser.parse_args()
    logger.info("Router invoked: depth=%d max_depth=%d", args.depth, args.max_depth)

    try:
        work_contents = os.listdir("/work")
        logger.debug("/work directory contents: %s", work_contents)
    except OSError as e:
        logger.warning("Cannot list /work directory: %s", e)

    state = load_state()

    if os.path.exists(EXPORT_CONFIG):
        decision = {"continue": False, "reason": "export_config.json exists"}
        logger.info("Decision: STOP -- export_config.json found")
    elif args.depth >= args.max_depth - 1:
        decision = {"continue": False, "reason": f"depth limit ({args.depth}/{args.max_depth})"}
        logger.info("Decision: STOP -- depth limit reached (%d/%d)", args.depth, args.max_depth)
    else:
        decision = {"continue": True, "reason": "export_config not found, continuing"}
        logger.info("Decision: CONTINUE -- depth %d/%d, no export_config", args.depth, args.max_depth)

    state["history"].append({
        "depth": args.depth,
        **decision,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
    save_state(state)

    output_value = "true" if decision["continue"] else "false"
    logger.info("Writing output to stdout: '%s'", output_value)
    print(output_value)


def run():
    """Entry point with error handling. Always produces output on stdout."""
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        logger.exception("Router crashed with unhandled exception")
        print("false")
        sys.exit(1)


if __name__ == "__main__":
    run()
