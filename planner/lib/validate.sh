#!/bin/bash
# Environment validation for planner.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh

# Validate that all required environment variables are set.
# Dies with a list of missing variables if any are unset.
validate_env() {
  local missing=()
  [ -z "${PROMPT:-}" ] && missing+=("PROMPT")
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Required env vars missing: ${missing[*]}"
  fi
}
