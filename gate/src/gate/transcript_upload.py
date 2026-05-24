"""Upload session transcripts (.jsonl) to the transcript viewer upload API.

For each transcript file the uploader performs a two-step exchange with the
viewer:

  1. POST {api_base_url}/api/transcripts/upload-url/{session_id}?file_name=<name>
     -> JSON body with a presigned ``url`` and the HTTP ``method`` to use.
  2. <method> <url> with the raw file bytes (Content-Type: application/jsonl).

The viewer owns the storage key layout, so the gate only supplies a session id
(URL path) and a file name (query parameter):

  <transcript_dir>/<session_id>.jsonl               -> file_name=<session_id>.jsonl
  <transcript_dir>/<session_id>/subagents/<f>.jsonl  -> file_name=subagents/<f>.jsonl
"""

from __future__ import annotations

import json
import logging
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from gate.config import TranscriptUploadConfig

logger = logging.getLogger("gate")

TRANSCRIPT_UPLOAD_CONCURRENCY = 5
TRANSCRIPT_CONTENT_TYPE = "application/jsonl"

# Mirrors the file names the viewer accepts; anything else is rejected with a
# 400, so we screen names out before spending a request on them.
_FILE_NAME_RE = re.compile(r"^(subagents/)?[A-Za-z0-9._-]+\.jsonl$")


class TranscriptUploader(Protocol):
    """Uploads a single transcript file, keyed by session id and file name."""

    def upload(self, session_id: str, file_name: str, body: bytes) -> None: ...


@dataclass(frozen=True, slots=True)
class UploadEntry:
    """A single file to upload: local path -> (session_id, file_name)."""

    session_id: str
    file_name: str
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
    """Build the upload list: main transcripts + their subagent transcripts.

    The viewer derives the storage key, so each entry carries only the session
    id and a file name. Subagent transcripts use a ``subagents/`` file-name
    prefix.
    """
    uploads: list[UploadEntry] = []
    for transcript_file in transcript_files:
        filename = os.path.basename(transcript_file)
        session_id = os.path.splitext(filename)[0]

        uploads.append(
            UploadEntry(
                session_id=session_id,
                file_name=f"{session_id}.jsonl",
                file_path=transcript_file,
            )
        )

        subagent_dir = os.path.join(transcript_dir, session_id, "subagents")
        if os.path.isdir(subagent_dir):
            for sub_file in os.listdir(subagent_dir):
                if sub_file.endswith(".jsonl"):
                    uploads.append(
                        UploadEntry(
                            session_id=session_id,
                            file_name=f"subagents/{sub_file}",
                            file_path=os.path.join(subagent_dir, sub_file),
                        )
                    )
    return uploads


class ViewerUploader:
    """Uploads transcripts through the viewer's presigned-URL upload API."""

    def __init__(self, api_base_url: str, timeout: float = 30.0) -> None:
        self._base_url = api_base_url.rstrip("/")
        self._timeout = timeout

    def upload(self, session_id: str, file_name: str, body: bytes) -> None:
        if not _FILE_NAME_RE.match(file_name):
            raise ValueError(f"Invalid transcript file name: {file_name!r}")
        url, method = self._request_upload_url(session_id, file_name)
        self._put_object(url, method, body)

    def _request_upload_url(self, session_id: str, file_name: str) -> tuple[str, str]:
        query = urlencode({"file_name": file_name})
        endpoint = (
            f"{self._base_url}/api/transcripts/upload-url/{quote(session_id, safe='')}?{query}"
        )
        req = Request(endpoint, method="POST")
        with urlopen(req, timeout=self._timeout) as resp:
            payload = json.loads(resp.read())
        return payload["url"], payload.get("method", "PUT")

    def _put_object(self, url: str, method: str, body: bytes) -> None:
        req = Request(
            url,
            data=body,
            method=method,
            headers={"Content-Type": TRANSCRIPT_CONTENT_TYPE},
        )
        with urlopen(req, timeout=self._timeout) as resp:
            resp.read()


def _upload_single(uploader: TranscriptUploader, entry: UploadEntry) -> None:
    """Read one transcript file and upload it via the viewer API."""
    logger.info("Uploading transcript: session=%s file=%s", entry.session_id, entry.file_name)
    with open(entry.file_path, "rb") as f:
        body = f.read()
    uploader.upload(session_id=entry.session_id, file_name=entry.file_name, body=body)


def upload_transcripts(
    transcript_dir: str,
    config: TranscriptUploadConfig,
    uploader: TranscriptUploader | None = None,
) -> int:
    """Upload all transcripts via the viewer upload API (best-effort per file).

    Args:
        transcript_dir: Path to the .transcripts directory.
        config: Viewer upload API configuration.
        uploader: Injectable uploader for testing. If None, a ViewerUploader is
            created from ``config``.

    Returns:
        Number of files uploaded successfully. Individual file failures are
        logged and skipped so one bad file does not abort the whole batch.
    """
    if uploader is None:
        uploader = ViewerUploader(config.api_base_url, config.timeout)

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

    succeeded = 0
    with ThreadPoolExecutor(
        max_workers=min(TRANSCRIPT_UPLOAD_CONCURRENCY, len(uploads))
    ) as executor:
        futures = {executor.submit(_upload_single, uploader, entry): entry for entry in uploads}
        for future in as_completed(futures):
            entry = futures[future]
            try:
                future.result()
                succeeded += 1
            except Exception:
                logger.exception("Failed to upload transcript: %s", entry.file_name)

    logger.info(
        "Uploaded %d/%d transcript file(s) to %s",
        succeeded,
        len(uploads),
        config.api_base_url,
    )
    return succeeded
