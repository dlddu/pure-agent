#!/bin/bash
# Prompt construction for claude-agent.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh

# Build the full prompt, injecting previous output for multi-cycle continuity.
# Outputs the combined prompt to stdout; logs to stderr.
build_prompt() {
  local prompt="$PROMPT"
  local previous_output="${PREVIOUS_OUTPUT:-}"

  if [ -n "$previous_output" ]; then
    log "Building prompt with previous context (${#previous_output} chars)"
    printf 'Previous output:\n%s\n\nContinue with:\n%s' "$previous_output" "$prompt"
  else
    log "Building prompt (first cycle)"
    printf '%s' "$prompt"
  fi
}
