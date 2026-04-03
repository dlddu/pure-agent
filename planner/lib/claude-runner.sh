#!/bin/bash
# Claude Code CLI execution and environment ID extraction for planner.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh, prompt.sh, mcp-config.sh

# Invoke Claude Code CLI with the routing prompt.
# Writes stream-json output to CLAUDE_OUTPUT.
# Returns 0 on success, 1 on failure.
# Sets CLAUDE_EXIT_CODE to the actual CLI exit code.
CLAUDE_EXIT_CODE=0
run_claude() {
  local full_prompt
  full_prompt="$(build_prompt)"

  local cmd=(
    claude -p "$full_prompt"
    --output-format stream-json
    --verbose
    --dangerously-skip-permissions
    --model haiku
  )
  if [ "$HAS_MCP_CONFIG" -eq 1 ] && [ -f "$MCP_CONFIG" ]; then
    cmd+=(--mcp-config "$MCP_CONFIG")
  fi
  if [ -n "$CLAUDE_MD_PATH" ] && [ -f "$CLAUDE_MD_PATH" ]; then
    cmd+=(--append-system-prompt "$CLAUDE_MD_PATH")
  fi

  log "Running Claude Code CLI ..."

  set +e
  "${cmd[@]}" > "$CLAUDE_OUTPUT" 2>&1
  CLAUDE_EXIT_CODE=$?
  set -e

  if [ "$CLAUDE_EXIT_CODE" -ne 0 ]; then
    warn "Claude CLI exited with status $CLAUDE_EXIT_CODE"
  fi

  local output_size=0
  [ -f "$CLAUDE_OUTPUT" ] && output_size=$(wc -c < "$CLAUDE_OUTPUT")
  log "Claude CLI exit=$CLAUDE_EXIT_CODE, output=${output_size} bytes"

  return 0
}

# Extract environment_id from Claude CLI stream-json output.
# Uses the jq filter at EXTRACT_ENV_FILTER.
# Outputs the environment_id to stdout (may be empty).
extract_environment_id() {
  if [ ! -s "$CLAUDE_OUTPUT" ]; then
    warn "Claude output file is empty or missing"
    return 0
  fi

  if [ ! -f "$EXTRACT_ENV_FILTER" ]; then
    warn "Missing jq filter: $EXTRACT_ENV_FILTER"
    return 0
  fi

  local result_text
  result_text=$(jq -rs -f "$EXTRACT_ENV_FILTER" "$CLAUDE_OUTPUT" 2>/dev/null) || {
    warn "jq extraction failed"
    return 0
  }

  if [ -z "$result_text" ] || [ "$result_text" = "null" ]; then
    warn "No parseable response from Claude CLI output"
    return 0
  fi

  # Extract environment_id from JSON object in result text
  local env_id
  env_id=$(echo "$result_text" | grep -oP '\{[^}]*\}' | head -1 | jq -r '.environment_id // empty' 2>/dev/null) || true

  if [ -n "$env_id" ]; then
    echo "$env_id"
  fi
}
