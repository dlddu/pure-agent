"""Tests for planner.cli -- CLI argument parsing, orchestration, error handling."""

import logging
import sys
from pathlib import Path

import pytest

from planner.cli import _write_fallback_output, main, run

# ── plan: integration ──────────────────────────────────────


class TestPlan:
    def test_next_environment_skips_llm(self, tmp_path, monkeypatch, caplog):
        """When --next-environment is set, planner resolves directly without LLM."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "planner",
                "--prompt",
                "some task",
                "--next-environment",
                "python-analysis",
                "--output",
                output_path,
            ],
        )
        with caplog.at_level(logging.INFO, logger="planner"):
            main()
        image = Path(output_path).read_text().strip()
        assert "python-agent" in image

    def test_next_environment_unknown_falls_back_to_default(self, tmp_path, monkeypatch, caplog):
        """Unknown next_environment falls back to default image."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "planner",
                "--prompt",
                "some task",
                "--next-environment",
                "nonexistent",
                "--output",
                output_path,
            ],
        )
        with caplog.at_level(logging.INFO, logger="planner"):
            main()
        image = Path(output_path).read_text().strip()
        assert "claude-agent" in image

    def test_empty_next_environment_triggers_llm(self, tmp_path, monkeypatch, caplog):
        """Empty next_environment triggers LLM-based selection (falls back without LLM gateway)."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.delenv("ANTHROPIC_BASE_URL", raising=False)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "planner",
                "--prompt",
                "some task",
                "--next-environment",
                "",
                "--output",
                output_path,
            ],
        )
        with caplog.at_level(logging.INFO, logger="planner"):
            main()
        image = Path(output_path).read_text().strip()
        assert "claude-agent" in image


# ── missing args ─────────────────────────────────────────


class TestMissingArgs:
    def test_missing_prompt_exits(self, tmp_path, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["planner", "--output", str(tmp_path / "out.txt")])
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 2

    def test_missing_output_exits(self, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["planner", "--prompt", "task"])
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 2


# ── _write_fallback_output ───────────────────────────────


class TestWriteFallbackOutput:
    def test_writes_default_image_when_output_arg_present(self, tmp_path, monkeypatch, caplog):
        out = str(tmp_path / "fallback.txt")
        monkeypatch.setattr(sys, "argv", ["planner", "--output", out])
        with caplog.at_level(logging.INFO, logger="planner"):
            _write_fallback_output()
        content = Path(out).read_text().strip()
        assert "claude-agent" in content

    def test_silently_returns_when_output_missing(self, tmp_path, monkeypatch, caplog):
        monkeypatch.setattr(sys, "argv", ["planner", "--prompt", "task"])
        with caplog.at_level(logging.INFO, logger="planner"):
            _write_fallback_output()
        assert list(tmp_path.iterdir()) == []


# ── run: error boundary ──────────────────────────────────


class TestRun:
    def test_crash_exits_with_code_1(self, tmp_path, monkeypatch, caplog):
        """If main() throws, run() exits 1."""
        output_path = str(tmp_path / "out.txt")
        monkeypatch.setattr(
            sys,
            "argv",
            ["planner", "--prompt", "task", "--output", output_path],
        )

        import planner.cli as cli_mod

        monkeypatch.setattr(cli_mod, "main", _raise_runtime)
        with caplog.at_level(logging.ERROR, logger="planner"):
            with pytest.raises(SystemExit) as exc_info:
                run()
        assert exc_info.value.code == 1

    def test_systemexit_propagates(self, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["planner"])
        with pytest.raises(SystemExit) as exc_info:
            run()
        assert exc_info.value.code == 2


# ── entrypoint ───────────────────────────────────────────


class TestEntryPoint:
    def test_runs_as_subprocess(self, work_env):
        from tests.conftest import run_subprocess

        result = run_subprocess(
            work_env,
            "--prompt",
            "some task",
            "--next-environment",
            "default",
            "--output",
            str(work_env / "output.txt"),
        )
        assert result.returncode == 0
        assert "claude-agent" in (work_env / "output.txt").read_text()


def _raise_runtime():
    raise RuntimeError("disk full")
