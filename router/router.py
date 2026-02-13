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
            with open(STATE_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            logger.warning("Failed to parse state file %s, starting fresh", STATE_PATH)
    return {"history": []}


def save_state(state):
    with open(STATE_PATH, "w") as f:
        json.dump(state, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Workflow router")
    parser.add_argument("--depth", type=int, required=True)
    parser.add_argument("--max-depth", type=int, required=True)
    args = parser.parse_args()
    logger.info("Router invoked: depth=%d max_depth=%d", args.depth, args.max_depth)

    state = load_state()
    logger.debug("Loaded state with %d history entries", len(state["history"]))

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

    print("true" if decision["continue"] else "false")


if __name__ == "__main__":
    main()
