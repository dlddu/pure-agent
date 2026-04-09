"""Upload session transcripts (.jsonl) from the work directory to S3.

Port of export-handler/src/services/transcript-upload.ts.

Directory structure:
  <transcript_dir>/<sessionId>.jsonl             -> s3://<bucket>/<prefix>/<sessionId>.jsonl
  <transcript_dir>/<sessionId>/subagents/*.jsonl -> s3://<bucket>/<prefix>/<sessionId>/<filename>.jsonl

The "<prefix>/" segment is omitted when no prefix is configured.
"""

from __future__ import annotations

import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Protocol

from gate.config import TranscriptUploadConfig

logger = logging.getLogger("gate")

TRANSCRIPT_UPLOAD_CONCURRENCY = 5
ASSUME_ROLE_SESSION_NAME = "gate-transcript-upload"


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


def _collect_uploads(
    transcript_dir: str, transcript_files: list[str], prefix: str = ""
) -> list[UploadEntry]:
    """Build the full list of uploads: main transcripts + subagent transcripts.

    If ``prefix`` is non-empty it is prepended to every S3 key (with a ``/`` separator).
    """

    def _key(suffix: str) -> str:
        return f"{prefix}/{suffix}" if prefix else suffix

    uploads: list[UploadEntry] = []
    for transcript_file in transcript_files:
        filename = os.path.basename(transcript_file)
        session_id = os.path.splitext(filename)[0]

        uploads.append(UploadEntry(key=_key(f"{session_id}.jsonl"), file_path=transcript_file))

        subagent_dir = os.path.join(transcript_dir, session_id, "subagents")
        if os.path.isdir(subagent_dir):
            for sub_file in os.listdir(subagent_dir):
                if sub_file.endswith(".jsonl"):
                    uploads.append(
                        UploadEntry(
                            key=_key(f"{session_id}/{sub_file}"),
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


def _assume_role_credentials(config: TranscriptUploadConfig) -> dict[str, str]:
    """Call STS AssumeRole and return temporary credentials as boto3 client kwargs."""
    import boto3

    sts_kwargs: dict[str, str] = {"region_name": config.region}
    if config.endpoint_url:
        sts_kwargs["endpoint_url"] = config.endpoint_url
    sts = boto3.client("sts", **sts_kwargs)
    logger.info("Assuming role for transcript upload: %s", config.assume_role_arn)
    response = sts.assume_role(
        RoleArn=config.assume_role_arn,
        RoleSessionName=ASSUME_ROLE_SESSION_NAME,
    )
    creds = response["Credentials"]
    return {
        "aws_access_key_id": creds["AccessKeyId"],
        "aws_secret_access_key": creds["SecretAccessKey"],
        "aws_session_token": creds["SessionToken"],
    }


def _create_s3_client(config: TranscriptUploadConfig) -> S3Uploader:
    """Build a boto3 S3 client, optionally using STS AssumeRole credentials."""
    import boto3

    client_kwargs: dict[str, str] = {"region_name": config.region}
    if config.endpoint_url:
        client_kwargs["endpoint_url"] = config.endpoint_url
    if config.assume_role_arn:
        client_kwargs.update(_assume_role_credentials(config))
    return boto3.client("s3", **client_kwargs)


def upload_transcripts(
    transcript_dir: str,
    config: TranscriptUploadConfig,
    uploader: S3Uploader | None = None,
) -> int:
    """Upload all transcripts to S3.

    Args:
        transcript_dir: Path to the .transcripts directory.
        config: AWS bucket/region configuration.
        uploader: Injectable S3 client for testing. If None, creates a real boto3 client
            (optionally using STS AssumeRole when ``config.assume_role_arn`` is set).

    Returns:
        Number of files uploaded.
    """
    if uploader is None:
        uploader = _create_s3_client(config)

    transcript_files = _find_transcript_files(transcript_dir)
    logger.info(
        "Found %d transcript file(s): %s",
        len(transcript_files),
        ", ".join(os.path.basename(f) for f in transcript_files),
    )

    if not transcript_files:
        logger.info("No transcript files found. Skipping upload.")
        return 0

    uploads = _collect_uploads(transcript_dir, transcript_files, config.prefix)

    with ThreadPoolExecutor(
        max_workers=min(TRANSCRIPT_UPLOAD_CONCURRENCY, len(uploads))
    ) as executor:
        futures = {
            executor.submit(_upload_single, uploader, config.bucket_name, entry): entry
            for entry in uploads
        }
        for future in as_completed(futures):
            future.result()

    logger.info(
        "Uploaded %d transcript file(s) to s3://%s/%s",
        len(uploads),
        config.bucket_name,
        f"{config.prefix}/" if config.prefix else "",
    )
    return len(uploads)
