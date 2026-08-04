"""Shared fixtures and helpers for gate tests."""

import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest

from gate.config import GateConfig

# ── Fixtures ──────────────────────────────────────────────


@pytest.fixture
def config(tmp_path) -> GateConfig:
    """Create a GateConfig pointing at tmp_path."""
    return GateConfig(transcript_dir=str(tmp_path / ".transcripts"))


@pytest.fixture
def work_env(tmp_path, monkeypatch) -> Path:
    """Set WORK_DIR env var to tmp_path for integration tests."""
    monkeypatch.setenv("WORK_DIR", str(tmp_path))
    monkeypatch.delenv("TRANSCRIPT_UPLOAD_API_URL", raising=False)
    return tmp_path


# ── Helpers ───────────────────────────────────────────────


def run_subprocess(work_env, *argv, env_extra=None):
    """Run gate as a subprocess."""
    env = {**os.environ, "WORK_DIR": str(work_env)}
    env.pop("TRANSCRIPT_UPLOAD_API_URL", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        [sys.executable, "-m", "gate", *argv],
        capture_output=True,
        text=True,
        env=env,
    )


def raise_runtime_error(*_args, **_kwargs):
    """Stub that always raises RuntimeError. Used to simulate crashes in tests."""
    raise RuntimeError("disk full")


def single_log(caplog, predicate, label="matching") -> logging.LogRecord:
    """Return the single log record matching predicate, or fail with a clear message."""
    matches = [r for r in caplog.records if predicate(r)]
    assert len(matches) == 1, f"Expected 1 {label} log, got {len(matches)}"
    return matches[0]
