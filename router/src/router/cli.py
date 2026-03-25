"""CLI entry point: argument parsing, orchestration, error handling."""

import argparse
import logging
import sys

from router import logic
from router.config import RouterConfig, TranscriptUploadConfig
from router.environments import resolve_image

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("router")


def main() -> None:
    parser = argparse.ArgumentParser(description="Workflow router")
    subparsers = parser.add_subparsers(dest="command")

    # ── gate: continue/stop decision (after agent) ──
    gate_parser = subparsers.add_parser("gate", help="Decide whether to continue the agent loop")
    gate_parser.add_argument("--depth", type=int, required=True)
    gate_parser.add_argument("--max-depth", type=int, required=True)
    gate_parser.add_argument("--export-config", type=str, default="{}", help="Export config JSON")
    gate_parser.add_argument("--output", type=str, required=True, help="Output file for decision")
    gate_parser.add_argument(
        "--env-output",
        type=str,
        default="",
        help="Output file for next_environment hint (extracted from export_config)",
    )

    # ── plan: image selection (before agent) ──
    plan_parser = subparsers.add_parser("plan", help="Select agent image for this cycle")
    plan_parser.add_argument("--prompt", type=str, required=True, help="Task prompt to analyze")
    plan_parser.add_argument("--output", type=str, required=True, help="Output file for image")
    plan_parser.add_argument(
        "--override-environment",
        type=str,
        default="",
        help="Environment ID override (skip LLM if set)",
    )

    args = parser.parse_args()

    if args.command == "gate":
        _gate(args)
    elif args.command == "plan":
        _plan(args)
    else:
        parser.print_help()
        parser.error("A subcommand is required: 'gate' or 'plan'")


def _gate(args: argparse.Namespace) -> None:
    """Gate: decide continue/stop and extract next_environment from export_config."""
    if args.depth < 0:
        raise SystemExit(2)
    if args.max_depth < 1:
        raise SystemExit(2)

    config = RouterConfig.from_env()

    continuing, reason, next_env_id = logic.should_continue(
        config, args.export_config, args.depth, args.max_depth
    )
    logger.info(
        "depth=%d/%d decision=%s reason=%s",
        args.depth,
        args.max_depth,
        "CONTINUE" if continuing else "STOP",
        reason,
    )

    logic.write_output("true" if continuing else "false", args.output)

    # Write next_environment hint (ID only, not resolved image)
    if args.env_output:
        logic.write_output(next_env_id or "", args.env_output)

    # Upload transcripts to S3 (independent of routing decision)
    _upload_transcripts(config)


def _plan(args: argparse.Namespace) -> None:
    """Plan: select agent image via override or LLM."""
    override = args.override_environment.strip()

    if override:
        image = resolve_image(override)
        logger.info("Planner: override environment=%s -> %s", override, image)
    else:
        from router.image_selector import select_image_via_llm

        image = select_image_via_llm(args.prompt)
        logger.info("Planner: LLM selected -> %s", image)

    logic.write_output(image, args.output)


def _upload_transcripts(config: RouterConfig) -> None:
    """Upload transcripts to S3 if AWS config is available. Failures are logged, not raised."""
    upload_config = TranscriptUploadConfig.from_env()
    if upload_config is None:
        logger.info("Transcript upload skipped: AWS_S3_BUCKET_NAME not configured")
        return

    try:
        from router.transcript_upload import upload_transcripts

        count = upload_transcripts(config.transcript_dir, upload_config)
        logger.info("Transcript upload complete: %d file(s)", count)
    except Exception:
        logger.exception("Transcript upload failed (non-fatal)")


def _write_fallback_output() -> None:
    """Extract --output from sys.argv and write 'false' as a safe default."""
    try:
        idx = sys.argv.index("--output")
        output_path = sys.argv[idx + 1]
        with open(output_path, "w") as f:
            f.write("false\n")
        logger.info("Wrote fallback output: false -> %s", output_path)
    except (ValueError, IndexError, OSError):
        pass  # Shell-level fallback will handle it


def run() -> None:
    """Entry point with error handling. Always produces output."""
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        logger.exception("Router crashed with unhandled exception")
        _write_fallback_output()
        sys.exit(1)
