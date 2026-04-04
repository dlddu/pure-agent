#!/bin/bash
# Planner transcript collection: save Claude CLI output to shared transcript directory.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

# Save the planner's Claude CLI output as a transcript file.
# Copies $CLAUDE_OUTPUT to $TRANSCRIPT_DIR/planner-<timestamp>.jsonl
# so the gate can discover and upload it to S3.
# Returns 0 always: transcript saving is best-effort.
save_planner_transcript() {
  if [ ! -s "$CLAUDE_OUTPUT" ]; then
    log "No planner output to save as transcript"
    return 0
  fi

  if ! mkdir -p "$TRANSCRIPT_DIR"; then
    warn "Failed to create transcript directory: $TRANSCRIPT_DIR"
    return 0
  fi

  local timestamp
  timestamp=$(date +%s)
  local transcript_file="$TRANSCRIPT_DIR/planner-${timestamp}.jsonl"

  if cp "$CLAUDE_OUTPUT" "$transcript_file" 2>/dev/null; then
    log "Saved planner transcript: $transcript_file ($(wc -c < "$CLAUDE_OUTPUT") bytes)"
  else
    warn "Failed to save planner transcript to: $transcript_file"
  fi
}
