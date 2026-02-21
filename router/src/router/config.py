"""Router configuration and filename constants."""

from __future__ import annotations

import os
from dataclasses import dataclass

# Filename constants (keep in sync with export-handler/src/constants.ts)
EXPORT_CONFIG_FILENAME = "export_config.json"
TRANSCRIPT_DIR_NAME = ".transcripts"


@dataclass(frozen=True, slots=True)
class RouterConfig:
    """Resolved file paths for the router."""

    export_config: str
    transcript_dir: str

    @classmethod
    def from_env(cls) -> RouterConfig:
        work_dir = os.environ.get("WORK_DIR", "/work")
        return cls(
            export_config=os.path.join(work_dir, EXPORT_CONFIG_FILENAME),
            transcript_dir=os.path.join(work_dir, TRANSCRIPT_DIR_NAME),
        )


@dataclass(frozen=True, slots=True)
class TranscriptUploadConfig:
    """AWS configuration for transcript uploads."""

    bucket_name: str
    region: str

    @classmethod
    def from_env(cls) -> TranscriptUploadConfig | None:
        """Return config if AWS_S3_BUCKET_NAME is set, else None (skip upload)."""
        bucket = os.environ.get("AWS_S3_BUCKET_NAME", "")
        if not bucket:
            return None
        region = os.environ.get("AWS_REGION", "ap-northeast-2")
        return cls(bucket_name=bucket, region=region)
