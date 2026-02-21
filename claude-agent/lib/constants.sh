#!/bin/bash
# Path constants for claude-agent entrypoint.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# All variables here are used by other sourced modules.
# shellcheck disable=SC2034
#
# ═══════════════════════════════════════════════════════════════
# EXTERNAL CONTRACT
# These file paths are consumed by other components.
# Changing them requires coordinated updates across:
#
# File/Path                          Consumer
# ─────────────────────────────────  ──────────────────────────
# /tmp/agent_result.txt              k8s/workflow-template.yaml
# /tmp/session_id.txt                k8s/workflow-template.yaml
# $WORK_DIR/.transcripts/            export-handler
# $WORK_DIR/last_agent_output.json   mcp-server session.ts
# ═══════════════════════════════════════════════════════════════

# ─── Shared paths (외부 컴포넌트가 읽음 — 이름 변경 금지) ────
# shellcheck source=../shared/defaults.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shared/defaults.sh"
WORK_DIR="${WORK_DIR:-$DEFAULT_WORK_DIR}"
readonly WORK_DIR
TRANSCRIPT_DIR="$WORK_DIR/.transcripts"               # export-handler
readonly TRANSCRIPT_DIR
AGENT_OUTPUT_COPY="$WORK_DIR/last_agent_output.json"   # mcp-server session.ts
readonly AGENT_OUTPUT_COPY

# ─── Argo output paths (workflow-template.yaml) ─────────────
RESULT_FILE="${RESULT_FILE:-/tmp/agent_result.txt}"
readonly RESULT_FILE
SESSION_ID_FILE="${SESSION_ID_FILE:-/tmp/session_id.txt}"
readonly SESSION_ID_FILE

# ─── Internal paths ─────────────────────────────────────────
CLAUDE_DIR="${CLAUDE_DIR:-/home/claude/.claude}"
readonly CLAUDE_DIR
AGENT_OUTPUT="${AGENT_OUTPUT:-/tmp/agent_output.json}"
readonly AGENT_OUTPUT
readonly MCP_CONFIG="$WORK_DIR/.mcp.json"
EXTRACT_RESULT_FILTER="${EXTRACT_RESULT_FILTER:-/home/claude/extract-result.jq}"
readonly EXTRACT_RESULT_FILTER
CLAUDE_MD_SOURCE="${CLAUDE_MD_SOURCE:-/home/claude/CLAUDE.md}"
readonly CLAUDE_MD_SOURCE
MCP_PORT="${MCP_PORT:-8080}"
readonly MCP_PORT

# ─── Result fallback ────────────────────────────────────────
readonly FALLBACK_RESULT="No output captured"
# IMPORTANT: This string must match the fallback in extract-result.jq line 23.
readonly PARSE_FAILED_RESULT="Output not parseable"
