"""Tests for router.transcript_upload -- S3 transcript upload logic."""

from pathlib import Path
from unittest.mock import MagicMock

import pytest

from router.config import TranscriptUploadConfig
from router.transcript_upload import (
    _collect_uploads,
    _find_transcript_files,
    upload_transcripts,
)


@pytest.fixture
def upload_config() -> TranscriptUploadConfig:
    return TranscriptUploadConfig(bucket_name="my-bucket", region="ap-northeast-2")


@pytest.fixture
def mock_s3() -> MagicMock:
    return MagicMock()


# ── _find_transcript_files ──────────────────────────────


class TestFindTranscriptFiles:
    def test_returns_empty_when_dir_missing(self, tmp_path):
        result = _find_transcript_files(str(tmp_path / "nonexistent"))
        assert result == []

    def test_returns_empty_when_dir_is_empty(self, tmp_path):
        result = _find_transcript_files(str(tmp_path))
        assert result == []

    def test_finds_jsonl_files(self, tmp_path):
        (tmp_path / "abc123.jsonl").write_text("")
        (tmp_path / "def456.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 2
        assert all(f.endswith(".jsonl") for f in result)

    def test_skips_non_jsonl_files(self, tmp_path):
        (tmp_path / "readme.txt").write_text("")
        (tmp_path / "data.json").write_text("")
        (tmp_path / "session.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 1

    def test_skips_empty_session_id(self, tmp_path):
        (tmp_path / ".jsonl").write_text("")
        (tmp_path / "valid.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 1
        assert "valid.jsonl" in result[0]


# ── _collect_uploads ────────────────────────────────────


class TestCollectUploads:
    def test_main_transcript_only(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        assert len(uploads) == 1
        assert uploads[0].key == "abc123.jsonl"

    def test_main_plus_subagents(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")
        (subagent_dir / "sub2.jsonl").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        keys = {u.key for u in uploads}
        assert keys == {"abc123.jsonl", "abc123/sub1.jsonl", "abc123/sub2.jsonl"}

    def test_no_subagent_dir(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        assert len(uploads) == 1

    def test_ignores_non_jsonl_in_subagents(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")
        (subagent_dir / "notes.txt").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        keys = {u.key for u in uploads}
        assert keys == {"abc123.jsonl", "abc123/sub1.jsonl"}


# ── upload_transcripts ──────────────────────────────────


class TestUploadTranscripts:
    def test_returns_zero_when_no_transcript_dir(self, tmp_path, upload_config, mock_s3):
        count = upload_transcripts(str(tmp_path / "nonexistent"), upload_config, mock_s3)
        assert count == 0
        mock_s3.put_object.assert_not_called()

    def test_returns_zero_when_no_jsonl_files(self, tmp_path, upload_config, mock_s3):
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 0

    def test_uploads_single_file(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("transcript data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 1
        mock_s3.put_object.assert_called_once_with(
            Bucket="my-bucket",
            Key="abc123.jsonl",
            Body=b"transcript data",
            ContentType="application/jsonl",
        )

    def test_uploads_with_subagents(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("main")
        sub_dir = tmp_path / "abc123" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "sub1.jsonl").write_text("sub1")
        (sub_dir / "sub2.jsonl").write_text("sub2")

        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 3
        assert mock_s3.put_object.call_count == 3

    def test_uploads_multiple_sessions(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "session1.jsonl").write_text("s1")
        (tmp_path / "session2.jsonl").write_text("s2")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 2

    def test_s3_error_propagates(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("data")
        mock_s3.put_object.side_effect = Exception("Access Denied")
        with pytest.raises(Exception, match="Access Denied"):
            upload_transcripts(str(tmp_path), upload_config, mock_s3)

    def test_uploads_only_main_when_subagents_dir_missing(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 1
        mock_s3.put_object.assert_called_once_with(
            Bucket="my-bucket",
            Key="abc123.jsonl",
            Body=b"data",
            ContentType="application/jsonl",
        )
