"""CLI entry point: argument parsing, orchestration, error handling."""

import argparse
import logging
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
        "--override-environment",
        type=str,
        default="",
        help="Environment ID override (skip LLM if set)",
    )

    args = parser.parse_args()

    override = args.override_environment.strip()

    if override:
        image = resolve_image(override)
        logger.info("override environment=%s -> %s", override, image)
    else:
        from planner.image_selector import select_image_via_llm

        image = select_image_via_llm(args.prompt)
        logger.info("LLM selected -> %s", image)

    _write_output(image, args.output)


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
