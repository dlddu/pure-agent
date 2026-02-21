"""Upload session transcripts (.jsonl) from the work directory to S3.

Port of export-handler/src/services/transcript-upload.ts.

Directory structure:
  <transcript_dir>/<sessionId>.jsonl             -> s3://<bucket>/<sessionId>.jsonl
  <transcript_dir>/<sessionId>/subagents/*.jsonl  -> s3://<bucket>/<sessionId>/<filename>.jsonl
"""

from __future__ import annotations

import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Protocol

from router.config import TranscriptUploadConfig

logger = logging.getLogger("router")

TRANSCRIPT_UPLOAD_CONCURRENCY = 5


class S3Uploader(Protocol):
    """Abstraction over S3 put_object for testability."""

    def put_object(self, *, Bucket: str, Key: str, Body: bytes, ContentType: str) -> None: ...


@dataclass(frozen=True, slots=True)
class UploadEntry:
    """A single file to upload: local path -> S3 key."""

    key: str
    file_path: str


def _find_transcript_files(transcript_dir: str) -> list[str]:
    """Return paths to .jsonl files in the transcript directory."""
    if not os.path.isdir(transcript_dir):
        return []
    return [
        os.path.join(transcript_dir, f)
        for f in os.listdir(transcript_dir)
        if f.endswith(".jsonl") and f != ".jsonl"
    ]


def _collect_uploads(transcript_dir: str, transcript_files: list[str]) -> list[UploadEntry]:
    """Build the full list of uploads: main transcripts + subagent transcripts."""
    uploads: list[UploadEntry] = []
    for transcript_file in transcript_files:
        filename = os.path.basename(transcript_file)
        session_id = os.path.splitext(filename)[0]

        uploads.append(UploadEntry(key=f"{session_id}.jsonl", file_path=transcript_file))

        subagent_dir = os.path.join(transcript_dir, session_id, "subagents")
        if os.path.isdir(subagent_dir):
            for sub_file in os.listdir(subagent_dir):
                if sub_file.endswith(".jsonl"):
                    uploads.append(
                        UploadEntry(
                            key=f"{session_id}/{sub_file}",
                            file_path=os.path.join(subagent_dir, sub_file),
                        )
                    )
    return uploads


def _upload_single(uploader: S3Uploader, bucket_name: str, entry: UploadEntry) -> None:
    """Upload a single file to S3."""
    logger.info("Uploading transcript: %s", entry.key)
    with open(entry.file_path, "rb") as f:
        body = f.read()
    uploader.put_object(
        Bucket=bucket_name, Key=entry.key, Body=body, ContentType="application/jsonl"
    )


def upload_transcripts(
    transcript_dir: str,
    config: TranscriptUploadConfig,
    uploader: S3Uploader | None = None,
) -> int:
    """Upload all transcripts to S3.

    Args:
        transcript_dir: Path to the .transcripts directory.
        config: AWS bucket/region configuration.
        uploader: Injectable S3 client for testing. If None, creates a real boto3 client.

    Returns:
        Number of files uploaded.
    """
    if uploader is None:
        import boto3

        uploader = boto3.client("s3", region_name=config.region)

    transcript_files = _find_transcript_files(transcript_dir)
    logger.info(
        "Found %d transcript file(s): %s",
        len(transcript_files),
        ", ".join(os.path.basename(f) for f in transcript_files),
    )

    if not transcript_files:
        logger.info("No transcript files found. Skipping upload.")
        return 0

    uploads = _collect_uploads(transcript_dir, transcript_files)

    with ThreadPoolExecutor(
        max_workers=min(TRANSCRIPT_UPLOAD_CONCURRENCY, len(uploads))
    ) as executor:
        futures = {
            executor.submit(_upload_single, uploader, config.bucket_name, entry): entry
            for entry in uploads
        }
        for future in as_completed(futures):
            future.result()

    logger.info("Uploaded %d transcript file(s) to s3://%s/", len(uploads), config.bucket_name)
    return len(uploads)
