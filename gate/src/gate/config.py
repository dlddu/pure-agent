"""Gate configuration and filename constants."""

from __future__ import annotations

import os
from dataclasses import dataclass

TRANSCRIPT_DIR_NAME = ".transcripts"


@dataclass(frozen=True, slots=True)
class GateConfig:
    """Resolved file paths for the gate."""

    transcript_dir: str

    @classmethod
    def from_env(cls) -> GateConfig:
        work_dir = os.environ.get("WORK_DIR", "/work")
        return cls(transcript_dir=os.path.join(work_dir, TRANSCRIPT_DIR_NAME))


@dataclass(frozen=True, slots=True)
class TranscriptUploadConfig:
    """Configuration for transcript uploads via the viewer upload API."""

    api_base_url: str
    timeout: float = 30.0

    @classmethod
    def from_env(cls) -> TranscriptUploadConfig | None:
        """Return config if TRANSCRIPT_UPLOAD_API_URL is set, else None (skip upload)."""
        api_base_url = os.environ.get("TRANSCRIPT_UPLOAD_API_URL", "")
        if not api_base_url:
            return None
        return cls(api_base_url=api_base_url)
