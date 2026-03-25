"""Shared fixtures and helpers for planner tests."""

import os
import subprocess
import sys
from pathlib import Path

import pytest


@pytest.fixture
def work_env(tmp_path, monkeypatch) -> Path:
    """Set WORK_DIR env var to tmp_path for integration tests."""
    monkeypatch.setenv("WORK_DIR", str(tmp_path))
    return tmp_path


def run_subprocess(work_env, *argv):
    """Run planner as a subprocess with additional args."""
    return subprocess.run(
        [sys.executable, "-m", "planner", *argv],
        capture_output=True,
        text=True,
        env={**os.environ, "WORK_DIR": str(work_env)},
    )
