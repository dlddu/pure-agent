"""Tests for planner.cli -- CLI argument parsing, orchestration, error handling."""

import json
import logging
import subprocess
import sys
from pathlib import Path

import pytest

from planner.cli import _write_fallback_output, main, run


def _make_completed_process(environment_id: str) -> subprocess.CompletedProcess:
    """Create a mock CompletedProcess with stream-json output."""
    result_text = json.dumps({"environment_id": environment_id})
    stdout = json.dumps({"type": "result", "result": result_text})
    return subprocess.CompletedProcess(args=["claude"], returncode=0, stdout=stdout, stderr="")


# ── plan: integration ──────────────────────────────────────


class TestPlan:
    def test_llm_selection_with_subprocess(self, tmp_path, monkeypatch, caplog):
        """Planner calls Claude Code CLI and produces output."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.delenv("MCP_HOST", raising=False)
        monkeypatch.setattr(
            sys,
            "argv",
            ["planner", "--prompt", "some task", "--output", output_path],
        )
        monkeypatch.setattr(
            "subprocess.run",
            lambda *a, **kw: _make_completed_process("default"),
        )
        with caplog.at_level(logging.INFO, logger="planner"):
            main()
        image = Path(output_path).read_text().strip()
        assert "claude-agent" in image

    def test_generates_mcp_config_when_host_set(self, tmp_path, monkeypatch, caplog):
        """When MCP_HOST is set, MCP config file is created."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.setenv("MCP_HOST", "mcp-server")
        monkeypatch.setattr(
            sys,
            "argv",
            ["planner", "--prompt", "some task", "--output", output_path],
        )
        monkeypatch.setattr(
            "subprocess.run",
            lambda *a, **kw: _make_completed_process("default"),
        )
        with caplog.at_level(logging.INFO, logger="planner"):
            main()
        # Verify MCP config was created
        assert "MCP config written" in caplog.text

    def test_fallback_when_cli_not_found(self, tmp_path, monkeypatch, caplog):
        """Without claude CLI, falls back to default image."""
        output_path = str(tmp_path / "image.txt")
        monkeypatch.delenv("MCP_HOST", raising=False)
        monkeypatch.setattr(
            sys,
            "argv",
            ["planner", "--prompt", "some task", "--output", output_path],
        )
        monkeypatch.setattr(
            "subprocess.run",
            lambda *a, **kw: (_ for _ in ()).throw(FileNotFoundError("claude not found")),
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


def _raise_runtime():
    raise RuntimeError("disk full")
