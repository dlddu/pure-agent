"""LLM-based agent image selection using the Anthropic API via LLM gateway."""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request

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
Respond with ONLY a JSON object: {{"environment_id": "<id>"}}

Selection guidelines:
- "default": General coding, code review, documentation, git operations
- "python-analysis": Data analysis, visualization, pandas/numpy, ML/AI
- "infra": Kubernetes, infrastructure, kubectl, Helm, AWS/cloud, deploy

If uncertain, choose "default"."""


def _build_system_prompt() -> str:
    """Build the system prompt with current environment descriptions."""
    env_lines = []
    for env in ENVIRONMENTS:
        caps = ", ".join(env.capabilities)
        env_lines.append(f'- id: "{env.id}" | {env.description} | capabilities: [{caps}]')
    return _SYSTEM_PROMPT.format(environments="\n".join(env_lines))


def select_image_via_llm(
    prompt: str,
    *,
    anthropic_base_url: str | None = None,
    api_key: str | None = None,
) -> tuple[str, str | None]:
    """Select the best agent image by asking the LLM.

    Args:
        prompt: The user task / prompt to analyze.
        anthropic_base_url: Base URL for the Anthropic API (e.g. LLM gateway).
        api_key: API key for authentication.

    Returns:
        (image, raw_environment_id) tuple. raw_environment_id is the value
        returned by the LLM before any fallback (None if LLM was not called).
    """
    base_url = anthropic_base_url or os.environ.get("ANTHROPIC_BASE_URL", "")
    key = api_key or os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")

    logger.info(
        "select_image_via_llm: base_url=%s key_prefix=%s key_len=%d",
        base_url[:40] if base_url else "(empty)",
        key[:8] if key else "(empty)",
        len(key),
    )

    if not base_url:
        logger.warning("ANTHROPIC_BASE_URL not set, falling back to default environment")
        return resolve_image(DEFAULT_ENVIRONMENT_ID), None

    url = f"{base_url.rstrip('/')}/v1/messages"
    headers: dict[str, str] = {
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01",
    }
    # API keys (sk-ant-* prefix) use x-api-key header; all others use Bearer auth.
    if key.startswith("sk-ant-"):
        headers["x-api-key"] = key
    else:
        headers["Authorization"] = f"Bearer {key}"
    body = json.dumps(
        {
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 100,
            "system": _build_system_prompt(),
            "messages": [{"role": "user", "content": prompt}],
        }
    ).encode()

    try:
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode())

        text = result.get("content", [{}])[0].get("text", "")
        logger.info("LLM response text: %s", text[:200])
        parsed = json.loads(text)
        raw_id = parsed.get("environment_id")
        logger.info("LLM raw response: environment_id=%s", raw_id)
        env_id = raw_id or DEFAULT_ENVIRONMENT_ID

        if env_id not in ENVIRONMENT_MAP:
            logger.warning("LLM returned unknown environment '%s', using default", env_id)
            env_id = DEFAULT_ENVIRONMENT_ID

        image = resolve_image(env_id)
        logger.info("LLM selected environment: %s -> %s", env_id, image)
        return image, raw_id

    except urllib.error.HTTPError as exc:
        err_body = ""
        try:
            err_body = exc.read().decode()[:300]
        except Exception:
            pass
        logger.warning("LLM HTTP %d: %s", exc.code, err_body)
        return resolve_image(DEFAULT_ENVIRONMENT_ID), f"HTTP_{exc.code}"
    except (urllib.error.URLError, json.JSONDecodeError, KeyError, TypeError) as exc:
        logger.warning("LLM image selection failed (%s: %s), falling back to default", type(exc).__name__, exc)
        return resolve_image(DEFAULT_ENVIRONMENT_ID), f"ERR_{type(exc).__name__}"
