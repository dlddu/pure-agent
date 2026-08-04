"""Tests for gate entry point -- subprocess execution via ``python -m gate``."""

from tests.conftest import run_subprocess


class TestEntryPoint:
    def test_gate_runs_as_subprocess(self, work_env):
        """python -m gate invokes run() via __main__.py and exits 0."""
        result = run_subprocess(work_env)
        assert result.returncode == 0
        assert "Transcript upload skipped" in result.stderr

    def test_gate_uploads_zero_files_when_configured(self, work_env):
        """With upload API configured but no transcripts, exits 0 with zero uploads."""
        result = run_subprocess(
            work_env, env_extra={"TRANSCRIPT_UPLOAD_API_URL": "http://viewer.test"}
        )
        assert result.returncode == 0
        assert "Transcript upload complete: 0 file(s)" in result.stderr
