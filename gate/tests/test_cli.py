"""Tests for gate.cli -- transcript upload orchestration and error handling."""

import logging

import pytest

from gate import cli
from gate.cli import main, run
from tests.conftest import raise_runtime_error, single_log

# ── main ─────────────────────────────────────────────────


class TestMain:
    def test_skips_upload_when_api_url_not_configured(self, work_env, caplog):
        with caplog.at_level(logging.INFO, logger="gate"):
            main()
        rec = single_log(caplog, lambda r: "skipped" in r.message, "skip")
        assert "TRANSCRIPT_UPLOAD_API_URL not configured" in rec.message

    def test_uploads_when_api_url_configured(self, work_env, monkeypatch, caplog):
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.test")

        calls = {}

        def fake_upload(transcript_dir, upload_config):
            calls["transcript_dir"] = transcript_dir
            calls["api_base_url"] = upload_config.api_base_url
            return 3

        from gate import transcript_upload

        monkeypatch.setattr(transcript_upload, "upload_transcripts", fake_upload)

        with caplog.at_level(logging.INFO, logger="gate"):
            main()

        assert calls["transcript_dir"] == str(work_env / ".transcripts")
        assert calls["api_base_url"] == "http://viewer.test"
        rec = single_log(caplog, lambda r: "complete" in r.message, "complete")
        assert rec.message == "Transcript upload complete: 3 file(s)"

    def test_uploads_zero_files_when_transcript_dir_missing(self, work_env, monkeypatch, caplog):
        """No transcripts on disk -> zero uploads, no error."""
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.test")
        with caplog.at_level(logging.INFO, logger="gate"):
            main()
        rec = single_log(caplog, lambda r: "complete" in r.message, "complete")
        assert rec.message == "Transcript upload complete: 0 file(s)"

    def test_propagates_upload_errors(self, work_env, monkeypatch):
        """main() itself does not swallow errors; run() does."""
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.test")

        from gate import transcript_upload

        monkeypatch.setattr(transcript_upload, "upload_transcripts", raise_runtime_error)

        with pytest.raises(RuntimeError):
            main()


# ── run ──────────────────────────────────────────────────


class TestRun:
    def test_run_completes_on_success(self, work_env, caplog):
        with caplog.at_level(logging.INFO, logger="gate"):
            run()
        assert "skipped" in caplog.text

    def test_run_swallows_upload_errors(self, work_env, monkeypatch, caplog):
        """Upload failures are logged as non-fatal and never raised."""
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.test")
        monkeypatch.setattr(cli, "main", raise_runtime_error)

        with caplog.at_level(logging.ERROR, logger="gate"):
            run()  # must not raise

        rec = single_log(caplog, lambda r: "non-fatal" in r.message, "non-fatal")
        assert rec.message == "Transcript upload failed (non-fatal)"
