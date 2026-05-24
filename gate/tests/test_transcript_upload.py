"""Tests for gate.transcript_upload -- viewer upload API logic."""

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from gate.config import TranscriptUploadConfig
from gate.transcript_upload import (
    ViewerUploader,
    _collect_uploads,
    _find_transcript_files,
    upload_transcripts,
)


@pytest.fixture
def upload_config() -> TranscriptUploadConfig:
    return TranscriptUploadConfig(api_base_url="http://viewer.test")


@pytest.fixture
def mock_uploader() -> MagicMock:
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
        assert uploads[0].session_id == "abc123"
        assert uploads[0].file_name == "abc123.jsonl"

    def test_main_plus_subagents(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")
        (subagent_dir / "sub2.jsonl").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        names = {(u.session_id, u.file_name) for u in uploads}
        assert names == {
            ("abc123", "abc123.jsonl"),
            ("abc123", "subagents/sub1.jsonl"),
            ("abc123", "subagents/sub2.jsonl"),
        }

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
        names = {(u.session_id, u.file_name) for u in uploads}
        assert names == {("abc123", "abc123.jsonl"), ("abc123", "subagents/sub1.jsonl")}

    def test_subagent_file_name_carries_subagents_prefix(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        sub = next(u for u in uploads if u.file_name != "abc123.jsonl")
        assert sub.session_id == "abc123"
        assert sub.file_name == "subagents/sub1.jsonl"


# ── upload_transcripts ──────────────────────────────────


class TestUploadTranscripts:
    def test_returns_zero_when_no_transcript_dir(self, tmp_path, upload_config, mock_uploader):
        count = upload_transcripts(str(tmp_path / "nonexistent"), upload_config, mock_uploader)
        assert count == 0
        mock_uploader.upload.assert_not_called()

    def test_returns_zero_when_no_jsonl_files(self, tmp_path, upload_config, mock_uploader):
        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 0

    def test_uploads_single_file(self, tmp_path, upload_config, mock_uploader):
        (tmp_path / "abc123.jsonl").write_text("transcript data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 1
        mock_uploader.upload.assert_called_once_with(
            session_id="abc123",
            file_name="abc123.jsonl",
            body=b"transcript data",
        )

    def test_uploads_with_subagents(self, tmp_path, upload_config, mock_uploader):
        (tmp_path / "abc123.jsonl").write_text("main")
        sub_dir = tmp_path / "abc123" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "sub1.jsonl").write_text("sub1")
        (sub_dir / "sub2.jsonl").write_text("sub2")

        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 3
        assert mock_uploader.upload.call_count == 3

    def test_uploads_multiple_sessions(self, tmp_path, upload_config, mock_uploader):
        (tmp_path / "session1.jsonl").write_text("s1")
        (tmp_path / "session2.jsonl").write_text("s2")
        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 2

    def test_subagent_uploaded_with_prefixed_file_name(
        self, tmp_path, upload_config, mock_uploader
    ):
        (tmp_path / "abc123.jsonl").write_text("main")
        sub_dir = tmp_path / "abc123" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "sub1.jsonl").write_text("sub")

        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 2
        names = {
            (c.kwargs["session_id"], c.kwargs["file_name"])
            for c in mock_uploader.upload.call_args_list
        }
        assert names == {("abc123", "abc123.jsonl"), ("abc123", "subagents/sub1.jsonl")}

    def test_best_effort_one_failure_does_not_abort_batch(self, tmp_path, upload_config):
        (tmp_path / "s1.jsonl").write_text("a")
        (tmp_path / "s2.jsonl").write_text("b")
        (tmp_path / "s3.jsonl").write_text("c")

        uploader = MagicMock()

        def fake_upload(*, session_id, file_name, body):
            if session_id == "s2":
                raise RuntimeError("upload failed")

        uploader.upload.side_effect = fake_upload

        count = upload_transcripts(str(tmp_path), upload_config, uploader)
        assert count == 2
        assert uploader.upload.call_count == 3

    def test_uploads_only_main_when_subagents_dir_missing(
        self, tmp_path, upload_config, mock_uploader
    ):
        (tmp_path / "abc123.jsonl").write_text("data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_uploader)
        assert count == 1
        mock_uploader.upload.assert_called_once_with(
            session_id="abc123",
            file_name="abc123.jsonl",
            body=b"data",
        )

    def test_default_uploader_is_viewer_uploader(self, tmp_path, upload_config):
        """When no uploader is injected, a ViewerUploader drives the 2-step exchange."""
        (tmp_path / "abc123.jsonl").write_text("data")

        captured = []

        def fake_urlopen(req, timeout=None):
            captured.append(req)
            if req.method == "POST":
                return _FakeResponse(
                    json.dumps(
                        {"url": "http://s3.test/bucket/abc123.jsonl", "method": "PUT"}
                    ).encode()
                )
            return _FakeResponse(b"")

        with patch("gate.transcript_upload.urlopen", side_effect=fake_urlopen):
            count = upload_transcripts(str(tmp_path), upload_config)

        assert count == 1
        assert [r.method for r in captured] == ["POST", "PUT"]


# ── ViewerUploader ──────────────────────────────────────


class _FakeResponse:
    """Minimal urlopen() response stand-in usable as a context manager."""

    def __init__(self, data: bytes = b"") -> None:
        self._data = data

    def read(self) -> bytes:
        return self._data

    def __enter__(self) -> "_FakeResponse":
        return self

    def __exit__(self, *_exc) -> bool:
        return False


class TestViewerUploader:
    def test_requests_upload_url_then_puts_body(self):
        captured = []

        def fake_urlopen(req, timeout=None):
            captured.append(req)
            if req.method == "POST":
                return _FakeResponse(
                    json.dumps(
                        {
                            "url": "http://s3.test/bucket/abc123/abc123.jsonl",
                            "method": "PUT",
                            "key": "abc123/abc123.jsonl",
                            "session_id": "abc123",
                            "expires_in": 3600,
                        }
                    ).encode()
                )
            return _FakeResponse(b"")

        uploader = ViewerUploader("http://viewer.test")
        with patch("gate.transcript_upload.urlopen", side_effect=fake_urlopen):
            uploader.upload(session_id="abc123", file_name="abc123.jsonl", body=b"payload")

        assert len(captured) == 2
        post_req, put_req = captured

        assert post_req.method == "POST"
        assert post_req.full_url == (
            "http://viewer.test/api/transcripts/upload-url/abc123?file_name=abc123.jsonl"
        )

        assert put_req.method == "PUT"
        assert put_req.full_url == "http://s3.test/bucket/abc123/abc123.jsonl"
        assert put_req.data == b"payload"
        assert put_req.get_header("Content-type") == "application/jsonl"

    def test_strips_trailing_slash_from_base_url(self):
        captured = []

        def fake_urlopen(req, timeout=None):
            captured.append(req)
            if req.method == "POST":
                return _FakeResponse(
                    json.dumps({"url": "http://s3.test/x", "method": "PUT"}).encode()
                )
            return _FakeResponse(b"")

        uploader = ViewerUploader("http://viewer.test/")
        with patch("gate.transcript_upload.urlopen", side_effect=fake_urlopen):
            uploader.upload(session_id="sess", file_name="sess.jsonl", body=b"x")

        assert captured[0].full_url == (
            "http://viewer.test/api/transcripts/upload-url/sess?file_name=sess.jsonl"
        )

    def test_subagent_file_name_is_url_encoded_in_query(self):
        captured = []

        def fake_urlopen(req, timeout=None):
            captured.append(req)
            if req.method == "POST":
                return _FakeResponse(
                    json.dumps({"url": "http://s3.test/x", "method": "PUT"}).encode()
                )
            return _FakeResponse(b"")

        uploader = ViewerUploader("http://viewer.test")
        with patch("gate.transcript_upload.urlopen", side_effect=fake_urlopen):
            uploader.upload(session_id="abc123", file_name="subagents/sub1.jsonl", body=b"x")

        assert captured[0].full_url == (
            "http://viewer.test/api/transcripts/upload-url/abc123?file_name=subagents%2Fsub1.jsonl"
        )

    def test_defaults_to_put_when_method_absent_in_response(self):
        captured = []

        def fake_urlopen(req, timeout=None):
            captured.append(req)
            if req.method == "POST":
                return _FakeResponse(json.dumps({"url": "http://s3.test/x"}).encode())
            return _FakeResponse(b"")

        uploader = ViewerUploader("http://viewer.test")
        with patch("gate.transcript_upload.urlopen", side_effect=fake_urlopen):
            uploader.upload(session_id="abc123", file_name="abc123.jsonl", body=b"x")

        assert captured[1].method == "PUT"

    def test_rejects_invalid_file_name_without_calling_api(self):
        uploader = ViewerUploader("http://viewer.test")
        with patch("gate.transcript_upload.urlopen") as mock_urlopen:
            with pytest.raises(ValueError, match="Invalid transcript file name"):
                uploader.upload(session_id="abc123", file_name="../escape.txt", body=b"x")
            mock_urlopen.assert_not_called()
