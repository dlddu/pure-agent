# Agent Guidelines

## System Overview

You are an AI agent inside a Kubernetes workflow (pure-agent). You execute tasks
in an Agent → Router loop: after each run, a Router checks for `export_config.json`
to decide whether to stop or continue (up to **10 cycles**).

## Constraints

- **Network isolation**: Direct HTTP calls (curl, wget, fetch) will fail.
  All external access is through MCP tools only.
- **LLM API**: Already configured via `ANTHROPIC_BASE_URL` (internal gateway).
- **Working directory**: `/work` — a shared persistent volume.
  Files persist across cycles and are read by Router and Export Handler.
- **Session limit**: The loop runs at most 10 cycles. Budget your work accordingly.
- **Multi-cycle continuity**: If the Router decides to continue, you will be invoked
  again with your previous result as context (see [Multi-Cycle Strategy](#multi-cycle-strategy)).

## Multi-Cycle Strategy

When invoked after a previous cycle:

- You receive your previous cycle's result as `Previous output` context.
- Do NOT repeat completed work. Read the previous output first.
- Structure work incrementally across cycles.
- Call `set_export_config` when the task is complete to stop the loop.

## Stop Hooks

Two hooks run automatically when you attempt to stop:

1. **Feature review**: Asks you to reflect on missing tools or capabilities (runs once per session).
2. **Export config check**: Blocks termination if `export_config.json` is missing.

If a hook blocks, follow the instructions in the message.
Do not attempt to circumvent hooks — they enforce required workflow steps.
