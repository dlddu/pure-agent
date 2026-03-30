"""Tests for planner.image_selector -- Claude Code CLI-based image selection."""

import json
import subprocess
from unittest.mock import MagicMock, patch

from planner.environments import DEFAULT_ENVIRONMENT_ID, ENVIRONMENT_MAP
from planner.image_selector import (
    _extract_environment_id,
    _parse_stream_json,
    select_image_via_llm,
)


def _make_stream_json(environment_id: str) -> str:
    """Build stream-json output with a result event containing the environment_id."""
    result_text = json.dumps({"environment_id": environment_id})
    lines = [
        json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "thinking..."}]}}),
        json.dumps({"type": "result", "result": result_text}),
    ]
    return "\n".join(lines)


def _make_completed_process(environment_id: str, returncode: int = 0) -> subprocess.CompletedProcess:
    """Create a mock CompletedProcess with stream-json output."""
    return subprocess.CompletedProcess(
        args=["claude"],
        returncode=returncode,
        stdout=_make_stream_json(environment_id),
        stderr="",
    )


class TestParseStreamJson:
    def test_extracts_result_text(self):
        stdout = _make_stream_json("python-analysis")
        text = _parse_stream_json(stdout)
        assert "python-analysis" in text

    def test_falls_back_to_assistant_text(self):
        """When no result event, falls back to last assistant text."""
        lines = [
            json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": '{"environment_id": "infra"}'}]}}),
        ]
        text = _parse_stream_json("\n".join(lines))
        assert "infra" in text

    def test_returns_none_for_empty(self):
        assert _parse_stream_json("") is None

    def test_ignores_malformed_json_lines(self):
        stdout = "not json\n" + json.dumps({"type": "result", "result": '{"environment_id": "default"}'})
        text = _parse_stream_json(stdout)
        assert "default" in text


class TestExtractEnvironmentId:
    def test_extracts_from_json(self):
        assert _extract_environment_id('{"environment_id": "infra"}') == "infra"

    def test_extracts_from_markdown_fenced_json(self):
        text = '```json\n{"environment_id": "python-analysis"}\n```'
        assert _extract_environment_id(text) == "python-analysis"

    def test_extracts_with_trailing_text(self):
        text = '{"environment_id": "infra"}\nThis task requires kubectl.'
        assert _extract_environment_id(text) == "infra"

    def test_returns_none_for_no_json(self):
        assert _extract_environment_id("I think you should use python") is None

    def test_returns_none_for_none(self):
        assert _extract_environment_id(None) is None


class TestSelectImageViaLlm:
    def test_selects_python_environment(self):
        with patch("subprocess.run", return_value=_make_completed_process("python-analysis")):
            image, raw_id = select_image_via_llm("pandas 데이터 분석")
        assert "python-agent" in image
        assert raw_id == "python-analysis"

    def test_selects_infra_environment(self):
        with patch("subprocess.run", return_value=_make_completed_process("infra")):
            image, raw_id = select_image_via_llm("kubectl deploy")
        assert "infra-agent" in image
        assert raw_id == "infra"

    def test_selects_default_environment(self):
        with patch("subprocess.run", return_value=_make_completed_process("default")):
            image, raw_id = select_image_via_llm("코드 리뷰")
        assert "claude-agent" in image
        assert raw_id == "default"

    def test_fallback_when_cli_not_found(self):
        with patch("subprocess.run", side_effect=FileNotFoundError("claude not found")):
            image, raw_id = select_image_via_llm("some task")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "_CLI_NOT_FOUND"

    def test_fallback_on_timeout(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="claude", timeout=120)):
            image, raw_id = select_image_via_llm("some task")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "_TIMEOUT"

    def test_fallback_on_empty_output(self):
        proc = subprocess.CompletedProcess(args=["claude"], returncode=0, stdout="", stderr="")
        with patch("subprocess.run", return_value=proc):
            image, raw_id = select_image_via_llm("some task")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "_PARSE_EMPTY"

    def test_unknown_environment_falls_back(self):
        with patch("subprocess.run", return_value=_make_completed_process("unknown-env")):
            image, raw_id = select_image_via_llm("something")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "unknown-env"

    def test_nonzero_exit_still_parses_output(self):
        """Even if CLI returns non-zero, still try to parse stdout."""
        with patch("subprocess.run", return_value=_make_completed_process("infra", returncode=1)):
            image, raw_id = select_image_via_llm("kubectl deploy")
        assert "infra-agent" in image
        assert raw_id == "infra"

    def test_passes_mcp_config_path(self, tmp_path):
        """When mcp_config_path exists, it's included in the command."""
        config_path = tmp_path / "mcp.json"
        config_path.write_text('{"mcpServers": {}}')

        with patch("subprocess.run", return_value=_make_completed_process("default")) as mock_run:
            select_image_via_llm("task", mcp_config_path=str(config_path))
        cmd = mock_run.call_args[0][0]
        assert "--mcp-config" in cmd
        assert str(config_path) in cmd

    def test_skips_mcp_config_when_missing(self):
        """When mcp_config_path doesn't exist, it's not included."""
        with patch("subprocess.run", return_value=_make_completed_process("default")) as mock_run:
            select_image_via_llm("task", mcp_config_path="/nonexistent/mcp.json")
        cmd = mock_run.call_args[0][0]
        assert "--mcp-config" not in cmd

    def test_malformed_llm_response_falls_back(self):
        """When LLM returns non-JSON text, falls back to default."""
        lines = [
            json.dumps({"type": "result", "result": "I think you should use python"}),
        ]
        proc = subprocess.CompletedProcess(
            args=["claude"], returncode=0, stdout="\n".join(lines), stderr=""
        )
        with patch("subprocess.run", return_value=proc):
            image, raw_id = select_image_via_llm("something")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id is None
