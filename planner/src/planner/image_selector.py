"""Claude Code CLI-based agent image selection with MCP tool access."""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess

from planner.environments import (
    DEFAULT_ENVIRONMENT_ID,
    ENVIRONMENT_MAP,
    ENVIRONMENTS,
    resolve_image,
)

logger = logging.getLogger("planner")

_SYSTEM_PROMPT = """\
You are a routing assistant that selects the best execution environment for an AI agent task.

Available environments:
{environments}

Analyze the task description and select the most appropriate environment.

Selection guidelines:
- "default": General coding, code review, documentation, git operations
- "python-analysis": Data analysis, visualization, pandas/numpy, ML/AI
- "infra": Kubernetes, infrastructure, kubectl, Helm, AWS/cloud, deploy

If the task prompt contains a Linear issue ID (e.g. DLD-123, PROJ-456), \
use the get_issue tool to read the issue details before making your decision.

After analysis, respond with ONLY a JSON object: {{"environment_id": "<id>"}}

If uncertain, choose "default"."""

_CLAUDE_TIMEOUT = 120


def _build_system_prompt() -> str:
    """Build the system prompt with current environment descriptions."""
    env_lines = []
    for env in ENVIRONMENTS:
        caps = ", ".join(env.capabilities)
        env_lines.append(f'- id: "{env.id}" | {env.description} | capabilities: [{caps}]')
    return _SYSTEM_PROMPT.format(environments="\n".join(env_lines))


def _build_claude_command(
    prompt: str,
    *,
    mcp_config_path: str | None = None,
    claude_md_path: str | None = None,
) -> list[str]:
    """Build the claude CLI command."""
    system_prompt = _build_system_prompt()
    full_prompt = f"{system_prompt}\n\n---\nTask:\n{prompt}"

    cmd = [
        "claude",
        "-p", full_prompt,
        "--output-format", "stream-json",
        "--dangerously-skip-permissions",
        "--model", "haiku",
    ]
    if mcp_config_path and os.path.isfile(mcp_config_path):
        cmd += ["--mcp-config", mcp_config_path]
    if claude_md_path and os.path.isfile(claude_md_path):
        cmd += ["--append-system-prompt", claude_md_path]
    return cmd


def _parse_stream_json(stdout: str) -> str | None:
    """Extract the result text from Claude Code stream-json output.

    Looks for the last ``type=="result"`` event and returns its ``.result``
    field. Falls back to concatenating text blocks from the last
    ``type=="assistant"`` event.
    """
    result_text = None
    last_assistant_text = None

    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        if event.get("type") == "result" and event.get("result"):
            result_text = event["result"]
        elif event.get("type") == "assistant":
            content = event.get("message", {}).get("content", [])
            texts = [block["text"] for block in content if block.get("type") == "text"]
            if texts:
                last_assistant_text = "".join(texts)

    return result_text or last_assistant_text


def _extract_environment_id(text: str | None) -> str | None:
    """Extract environment_id from LLM response text."""
    if not text:
        return None
    match = re.search(r"\{[^}]*\}", text)
    if not match:
        return None
    try:
        parsed = json.loads(match.group())
    except json.JSONDecodeError:
        return None
    return parsed.get("environment_id")


def select_image_via_llm(
    prompt: str,
    *,
    mcp_config_path: str | None = None,
    claude_md_path: str | None = None,
) -> tuple[str, str | None]:
    """Select the best agent image by running Claude Code CLI.

    Args:
        prompt: The user task / prompt to analyze.
        mcp_config_path: Path to MCP config JSON (enables tool access).
        claude_md_path: Path to planner CLAUDE.md guidelines.

    Returns:
        (image, raw_environment_id) tuple. raw_environment_id is the value
        returned by the LLM before any fallback (None if LLM was not called).
    """
    cmd = _build_claude_command(
        prompt,
        mcp_config_path=mcp_config_path,
        claude_md_path=claude_md_path,
    )
    logger.info("Running Claude Code CLI: %s", " ".join(cmd[:4]) + " ...")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=_CLAUDE_TIMEOUT,
            env={**os.environ},
        )
    except FileNotFoundError:
        logger.warning("claude CLI not found, falling back to default environment")
        return resolve_image(DEFAULT_ENVIRONMENT_ID), "_CLI_NOT_FOUND"
    except subprocess.TimeoutExpired:
        logger.warning("claude CLI timed out after %ds, falling back to default", _CLAUDE_TIMEOUT)
        return resolve_image(DEFAULT_ENVIRONMENT_ID), "_TIMEOUT"

    if result.returncode != 0:
        logger.warning(
            "claude CLI exited with code %d: %s",
            result.returncode,
            result.stderr[:500] if result.stderr else "(no stderr)",
        )

    stdout = result.stdout or ""
    logger.info("Claude CLI output: %d bytes", len(stdout))

    response_text = _parse_stream_json(stdout)
    if not response_text:
        logger.warning("No parseable response from Claude CLI output")
        return resolve_image(DEFAULT_ENVIRONMENT_ID), "_PARSE_EMPTY"

    raw_id = _extract_environment_id(response_text)
    logger.info("LLM raw response: environment_id=%s", raw_id)

    env_id = raw_id or DEFAULT_ENVIRONMENT_ID
    if env_id not in ENVIRONMENT_MAP:
        logger.warning("LLM returned unknown environment '%s', using default", env_id)
        env_id = DEFAULT_ENVIRONMENT_ID

    image = resolve_image(env_id)
    logger.info("LLM selected environment: %s -> %s", env_id, image)
    return image, raw_id
