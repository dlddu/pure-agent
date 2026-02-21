#!/bin/bash
# Claude Code CLI execution and result extraction.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh
# run_claude also depends on: prompt.sh (build_prompt)

# Invoke Claude Code CLI with the built prompt.
# Writes stream-json output to both AGENT_OUTPUT and AGENT_OUTPUT_COPY.
# Returns the claude CLI exit code (0 = success).
run_claude() {
  local full_prompt
  full_prompt="$(build_prompt)"

  # The entrypoint runs under set -euo pipefail. Without set +e, a non-zero
  # claude exit would immediately kill the script before we can capture the code.
  # PIPESTATUS[0] captures claude's exit code specifically, ignoring tee's status.
  set +e
  claude -p "$full_prompt" \
    --dangerously-skip-permissions \
    --output-format stream-json \
    --verbose \
    | tee "$AGENT_OUTPUT" "$AGENT_OUTPUT_COPY"
  local exit_code="${PIPESTATUS[0]}"
  set -e

  if [ "$exit_code" -ne 0 ]; then
    warn "claude exited with status $exit_code"
  fi
  return "$exit_code"
}

# Extract the agent's final result from stream-json output using jq.
# Writes the result to RESULT_FILE. Falls back to FALLBACK_RESULT on failure.
# Returns 0 always: extraction is best-effort so the agent pipeline
# continues even if result parsing fails.
extract_result() {
  if [ ! -s "$AGENT_OUTPUT" ]; then
    warn "Agent output file is empty or missing"
    echo "$FALLBACK_RESULT" > "$RESULT_FILE"
    log "Result extracted (fallback, 0 bytes input)"
    return 0
  fi

  local jq_err
  if ! jq_err=$(jq -rs -f "$EXTRACT_RESULT_FILTER" "$AGENT_OUTPUT" 2>&1 >"$RESULT_FILE"); then
    warn "jq extraction failed: $jq_err"
    echo "$PARSE_FAILED_RESULT" > "$RESULT_FILE"
  fi

  log "Result extracted ($(wc -c < "$RESULT_FILE") bytes)"
}
