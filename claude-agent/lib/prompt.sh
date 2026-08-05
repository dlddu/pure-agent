#!/bin/bash
# Prompt construction for claude-agent.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh

# Build the full prompt for the one-shot run.
# Outputs the prompt to stdout; logs to stderr.
build_prompt() {
  log "Building prompt (${#PROMPT} chars)"
  printf '%s' "$PROMPT"
}
