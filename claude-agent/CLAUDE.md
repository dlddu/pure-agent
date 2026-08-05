# Agent Guidelines

## System Overview

You are an AI agent inside a Kubernetes workflow (pure-agent). You execute the
task in a single one-shot run: when you finish, the workflow exports your
results and terminates. There is no follow-up cycle, so complete the task
within this session.

## Constraints

- **Network isolation**: Direct HTTP calls (curl, wget, fetch) will fail.
  All external access is through MCP tools only.
- **LLM API**: Already configured via `ANTHROPIC_BASE_URL` (internal gateway).
- **Working directory**: `/work` — a shared persistent volume.
  Files written here are read by the Export Handler after you finish.
- **One-shot execution**: This is your only run for the task. Budget your work
  accordingly and finish everything before stopping.

## Finishing Up

Before you stop, call `set_export_config` to declare how your results should
be exported. Use `get_export_actions` to see the available actions and their
required fields. If the task could not be completed, set `actions: ["none"]`
and describe the current state and reason in `summary`.

## Stop Hooks

Two hooks run automatically when you attempt to stop:

1. **Feature review**: Asks you to reflect on missing tools or capabilities (runs once per session).
2. **Export config check**: Blocks termination if `export_config.json` is missing.

If a hook blocks, follow the instructions in the message.
Do not attempt to circumvent hooks — they enforce required workflow steps.
