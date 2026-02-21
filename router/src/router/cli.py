"""CLI entry point: argument parsing, orchestration, error handling."""

import argparse
import logging
import sys

from router import logic
from router.config import RouterConfig, TranscriptUploadConfig

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("router")


def main() -> None:
    parser = argparse.ArgumentParser(description="Workflow router")
    parser.add_argument("--depth", type=int, required=True)
    parser.add_argument("--max-depth", type=int, required=True)
    parser.add_argument("--export-config", type=str, default="{}", help="Export config JSON")
    parser.add_argument("--output", type=str, required=True, help="Output file path")
    args = parser.parse_args()

    if args.depth < 0:
        parser.error(f"--depth must be >= 0, got {args.depth}")
    if args.max_depth < 1:
        parser.error(f"--max-depth must be >= 1, got {args.max_depth}")

    config = RouterConfig.from_env()

    continuing, reason = logic.should_continue(
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

    # Upload transcripts to S3 (independent of routing decision)
    _upload_transcripts(config)


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
