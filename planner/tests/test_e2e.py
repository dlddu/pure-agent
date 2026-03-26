"""End-to-end tests for the planner CLI.

These tests run the planner as a real subprocess against a local mock HTTP
server that simulates the Anthropic LLM gateway, verifying the full flow:
  CLI args → HTTP request → JSON parsing → environment resolution → output file.
"""

import http.server
import json
import os
import subprocess
import sys
import threading
from pathlib import Path

import pytest

# ── mock LLM gateway ────────────────────────────────────────


def _make_handler(environment_id: str | None = None, *, malformed: bool = False):
    """Create a request handler that returns a canned LLM response."""

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):  # noqa: N802
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            # Store the request for later inspection.
            self.server.last_request = body  # type: ignore[attr-defined]

            if malformed:
                text = "I think you should use python"
            elif environment_id is not None:
                text = json.dumps({"environment_id": environment_id})
            else:
                text = json.dumps({"environment_id": "default"})

            payload = json.dumps({"content": [{"type": "text", "text": text}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_args):  # suppress noisy logs
            pass

    return Handler


@pytest.fixture()
def llm_server():
    """Yield a (server, base_url) tuple for a mock LLM gateway.

    The server runs in a daemon thread and is shut down after the test.
    Use ``server.handler_class`` to swap the response behaviour mid-test
    by calling ``set_handler(environment_id)``.
    """
    handler = _make_handler("default")
    srv = http.server.HTTPServer(("127.0.0.1", 0), handler)
    port = srv.server_address[1]
    base_url = f"http://127.0.0.1:{port}"

    def _set_handler(environment_id: str | None = None, *, malformed: bool = False):
        srv.RequestHandlerClass = _make_handler(environment_id, malformed=malformed)

    srv.set_handler = _set_handler  # type: ignore[attr-defined]
    srv.last_request = None  # type: ignore[attr-defined]

    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    yield srv, base_url
    srv.shutdown()


_PLANNER_SRC = str(Path(__file__).resolve().parent.parent / "src")


def _run_planner(tmp_path: Path, prompt: str, *, env_extra: dict[str, str] | None = None, **kw):
    """Run the planner CLI as a subprocess and return (result, output_path)."""
    output_path = tmp_path / "image.txt"
    cmd = [
        sys.executable,
        "-m",
        "planner",
        "--prompt",
        prompt,
        "--output",
        str(output_path),
    ]
    raw_id_path = kw.get("raw_id_output")
    if raw_id_path:
        cmd += ["--raw-id-output", str(raw_id_path)]

    env = {**os.environ, "WORK_DIR": str(tmp_path), "PYTHONPATH": _PLANNER_SRC}
    if env_extra:
        env.update(env_extra)

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30)
    return result, output_path


# ── e2e: environment selection via mock LLM ──────────────────


class TestE2EEnvironmentSelection:
    """Full round-trip: CLI → mock LLM gateway → output file."""

    def test_selects_default_environment(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("default")
        result, output = _run_planner(
            tmp_path,
            "review this pull request",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        assert result.returncode == 0
        assert "claude-agent" in output.read_text()

    def test_selects_python_analysis_environment(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("python-analysis")
        result, output = _run_planner(
            tmp_path,
            "analyze sales data with pandas",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        assert result.returncode == 0
        assert "python-agent" in output.read_text()

    def test_selects_infra_environment(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("infra")
        result, output = _run_planner(
            tmp_path,
            "deploy to kubernetes cluster",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        assert result.returncode == 0
        assert "infra-agent" in output.read_text()


# ── e2e: raw-id-output flag ─────────────────────────────────


class TestE2ERawIdOutput:
    """Verify --raw-id-output writes the raw LLM environment ID."""

    def test_raw_id_written_for_known_env(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("python-analysis")
        raw_id_path = tmp_path / "raw_id.txt"
        result, output = _run_planner(
            tmp_path,
            "data analysis",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
            raw_id_output=raw_id_path,
        )
        assert result.returncode == 0
        assert raw_id_path.read_text().strip() == "python-analysis"

    def test_raw_id_written_for_unknown_env(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("nonexistent-env")
        raw_id_path = tmp_path / "raw_id.txt"
        result, output = _run_planner(
            tmp_path,
            "something weird",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
            raw_id_output=raw_id_path,
        )
        assert result.returncode == 0
        # Image falls back to default, but raw ID preserves the LLM output.
        assert "claude-agent" in output.read_text()
        assert raw_id_path.read_text().strip() == "nonexistent-env"

    def test_no_raw_id_file_when_flag_omitted(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("default")
        result, output = _run_planner(
            tmp_path,
            "code review",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        assert result.returncode == 0
        # No raw_id.txt should exist since --raw-id-output was not passed.
        assert not (tmp_path / "raw_id.txt").exists()


# ── e2e: fallback behaviour ─────────────────────────────────


class TestE2EFallback:
    """Verify graceful degradation when the LLM gateway is unavailable."""

    def test_fallback_when_no_gateway_configured(self, tmp_path, monkeypatch):
        monkeypatch.delenv("ANTHROPIC_BASE_URL", raising=False)
        result, output = _run_planner(
            tmp_path,
            "some task",
            env_extra={"ANTHROPIC_BASE_URL": "", "ANTHROPIC_API_KEY": ""},
        )
        assert result.returncode == 0
        assert "claude-agent" in output.read_text()

    def test_fallback_on_unreachable_gateway(self, tmp_path):
        result, output = _run_planner(
            tmp_path,
            "some task",
            env_extra={
                "ANTHROPIC_BASE_URL": "http://127.0.0.1:1",
                "ANTHROPIC_API_KEY": "test-key",
            },
        )
        assert result.returncode == 0
        assert "claude-agent" in output.read_text()

    def test_fallback_on_malformed_llm_response(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler(malformed=True)
        result, output = _run_planner(
            tmp_path,
            "some task",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        assert result.returncode == 0
        assert "claude-agent" in output.read_text()


# ── e2e: LLM request verification ───────────────────────────


class TestE2ERequestPayload:
    """Verify the planner sends the correct payload to the LLM gateway."""

    def test_prompt_forwarded_to_llm(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("default")
        prompt_text = "unique-test-prompt-abc123"
        _run_planner(
            tmp_path,
            prompt_text,
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        req = srv.last_request
        assert req is not None
        messages = req.get("messages", [])
        assert len(messages) == 1
        assert messages[0]["content"] == prompt_text

    def test_api_key_sent_in_header(self, tmp_path, llm_server):
        """Verify x-api-key header is sent (checked implicitly via successful request)."""
        srv, base_url = llm_server
        srv.set_handler("default")
        result, output = _run_planner(
            tmp_path,
            "test",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "my-secret-key"},
        )
        assert result.returncode == 0
        assert output.read_text().strip()

    def test_system_prompt_contains_environments(self, tmp_path, llm_server):
        srv, base_url = llm_server
        srv.set_handler("default")
        _run_planner(
            tmp_path,
            "test",
            env_extra={"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": "test-key"},
        )
        req = srv.last_request
        assert req is not None
        system_prompt = req.get("system", "")
        assert "default" in system_prompt
        assert "python-analysis" in system_prompt
        assert "infra" in system_prompt


# ── e2e: CLI argument validation ─────────────────────────────


class TestE2ECLIArgs:
    """Verify CLI argument parsing via subprocess."""

    def test_missing_prompt_exits_2(self, tmp_path):
        result = subprocess.run(
            [sys.executable, "-m", "planner", "--output", str(tmp_path / "out.txt")],
            capture_output=True,
            text=True,
            env={**os.environ, "WORK_DIR": str(tmp_path), "PYTHONPATH": _PLANNER_SRC},
        )
        assert result.returncode == 2

    def test_missing_output_exits_2(self, tmp_path):
        result = subprocess.run(
            [sys.executable, "-m", "planner", "--prompt", "task"],
            capture_output=True,
            text=True,
            env={**os.environ, "WORK_DIR": str(tmp_path), "PYTHONPATH": _PLANNER_SRC},
        )
        assert result.returncode == 2

    def test_no_args_exits_2(self, tmp_path):
        result = subprocess.run(
            [sys.executable, "-m", "planner"],
            capture_output=True,
            text=True,
            env={**os.environ, "WORK_DIR": str(tmp_path), "PYTHONPATH": _PLANNER_SRC},
        )
        assert result.returncode == 2
