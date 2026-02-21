#!/bin/bash
# Environment validation for claude-agent.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh

# Validate that all required environment variables are set.
# Dies with a list of missing variables if any are unset.
validate_env() {
  local missing=()
  [ -z "${PROMPT:-}" ]   && missing+=("PROMPT")
  [ -z "${MCP_HOST:-}" ] && missing+=("MCP_HOST")
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Required env vars missing: ${missing[*]}"
  fi
}
