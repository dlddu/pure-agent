"""CLI entry point: transcript upload orchestration and error handling."""

import logging
import sys

from gate.config import GateConfig, TranscriptUploadConfig

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("gate")


def main() -> None:
    """Upload session transcripts via the viewer API, if configured."""
    config = GateConfig.from_env()

    upload_config = TranscriptUploadConfig.from_env()
    if upload_config is None:
        logger.info("Transcript upload skipped: TRANSCRIPT_UPLOAD_API_URL not configured")
        return

    from gate.transcript_upload import upload_transcripts

    count = upload_transcripts(config.transcript_dir, upload_config)
    logger.info("Transcript upload complete: %d file(s)", count)


def run() -> None:
    """Entry point with error handling.

    Transcript upload is best-effort: failures are logged but never fail
    the workflow step.
    """
    try:
        main()
    except Exception:
        logger.exception("Transcript upload failed (non-fatal)")
