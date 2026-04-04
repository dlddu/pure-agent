#!/bin/bash
# Path constants for planner entrypoint.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# shellcheck disable=SC2034
#
# ═══════════════════════════════════════════════════════════════
# EXTERNAL CONTRACT
# These file paths are consumed by other components.
# Changing them requires coordinated updates across:
#
# File/Path                          Consumer
# ─────────────────────────────────  ──────────────────────────
# /tmp/agent_image.txt               k8s/workflow-template.yaml
# /tmp/raw_environment_id.txt        k8s/workflow-template.yaml
# /tmp/planner_debug.log             k8s/workflow-template.yaml (stderr)
# $WORK_DIR/last_planner_output.json mcp-server session.ts
# ═══════════════════════════════════════════════════════════════

# ─── Shared volume paths ───────────────────────────────────
WORK_DIR="${WORK_DIR:-/work}"
readonly WORK_DIR
TRANSCRIPT_DIR="${WORK_DIR}/.transcripts"
readonly TRANSCRIPT_DIR
PLANNER_OUTPUT_COPY="$WORK_DIR/last_planner_output.json"   # mcp-server session.ts
readonly PLANNER_OUTPUT_COPY

# ─── Internal paths ─────────────────────────────────────────
CLAUDE_OUTPUT="${CLAUDE_OUTPUT:-/tmp/planner_claude_output.json}"
readonly CLAUDE_OUTPUT
MCP_CONFIG="${MCP_CONFIG:-/tmp/planner_mcp.json}"
readonly MCP_CONFIG
MCP_PORT="${MCP_PORT:-8080}"
readonly MCP_PORT
CLAUDE_MD_PATH="${PLANNER_CLAUDE_MD:-}"
readonly CLAUDE_MD_PATH

# ─── jq filter ──────────────────────────────────────────────
EXTRACT_ENV_FILTER="${EXTRACT_ENV_FILTER:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/extract-environment.jq}"
readonly EXTRACT_ENV_FILTER

# ─── Default image (fallback) ──────────────────────────────
readonly DEFAULT_IMAGE="ghcr.io/dlddu/pure-agent/claude-agent:latest"
