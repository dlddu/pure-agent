"""Shared fixtures and helpers for router tests."""

import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest

from router import logic
from router.config import RouterConfig

# ── Fixtures ──────────────────────────────────────────────


@pytest.fixture
def config(tmp_path) -> RouterConfig:
    """Create a RouterConfig pointing at tmp_path."""
    return RouterConfig(
        export_config=str(tmp_path / "export_config.json"),
        transcript_dir=str(tmp_path / ".transcripts"),
    )


@pytest.fixture
def work_env(tmp_path, monkeypatch) -> Path:
    """Set WORK_DIR env var to tmp_path for integration tests."""
    monkeypatch.setenv("WORK_DIR", str(tmp_path))
    return tmp_path


@pytest.fixture
def run_env(work_env, monkeypatch):
    """Set up a normal run scenario: valid argv for depth=0, max_depth=5."""
    output_path = str(work_env / "output.txt")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "router",
            "--depth",
            "0",
            "--max-depth",
            "5",
            "--export-config",
            "{}",
            "--output",
            output_path,
        ],
    )
    return output_path


@pytest.fixture
def crash_env(work_env, monkeypatch):
    """Set up a crash scenario: should_continue raises, argv is configured."""
    monkeypatch.setattr(logic, "should_continue", raise_runtime_error)
    output_path = str(work_env / "output.txt")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "router",
            "--depth",
            "0",
            "--max-depth",
            "5",
            "--export-config",
            "{}",
            "--output",
            output_path,
        ],
    )
    return output_path


# ── Helpers ───────────────────────────────────────────────

OUTPUT_PLACEHOLDER = "OUTPUT"


def run_main(monkeypatch, work_env, depth, max_depth, export_config="{}"):
    """Set sys.argv and call main(), return output file content."""
    from router.cli import main

    output_path = str(work_env / "output.txt")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "router",
            "--depth",
            str(depth),
            "--max-depth",
            str(max_depth),
            "--export-config",
            export_config,
            "--output",
            output_path,
        ],
    )
    main()
    return Path(output_path).read_text()


def run_subprocess(work_env, *argv):
    """Run router as a subprocess with --output pointing to work_env/output.txt."""
    output_path = str(work_env / "output.txt")
    return subprocess.run(
        [sys.executable, "-m", "router", *argv, "--output", output_path],
        capture_output=True,
        text=True,
        env={**os.environ, "WORK_DIR": str(work_env)},
    )


def raise_runtime_error(*_args, **_kwargs):
    """Stub that always raises RuntimeError. Used to simulate crashes in tests."""
    raise RuntimeError("disk full")


def single_log(caplog, predicate, label="matching") -> logging.LogRecord:
    """Return the single log record matching predicate, or fail with a clear message."""
    matches = [r for r in caplog.records if predicate(r)]
    assert len(matches) == 1, f"Expected 1 {label} log, got {len(matches)}"
    return matches[0]


def decision_message(caplog) -> str:
    """Extract the single decision log message from captured records."""
    return single_log(caplog, lambda r: "decision=" in r.message, "decision").message
