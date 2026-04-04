#!/bin/bash
# Planner transcript collection: copy Claude CLI session transcripts to shared volume.
# Uses the same approach as claude-agent: find session .jsonl files in CLAUDE_DIR/projects
# and copy them (with their UUID filenames) to TRANSCRIPT_DIR for gate to upload to S3.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

CLAUDE_DIR="${CLAUDE_DIR:-/home/claude/.claude}"

# Find Claude CLI session transcript files.
# Returns file paths sorted by mtime (oldest first).
_find_planner_transcripts() {
  if [ ! -d "$CLAUDE_DIR/projects" ]; then
    log "No projects directory found at $CLAUDE_DIR/projects"
    return 0
  fi
  find "$CLAUDE_DIR/projects" -name "*.jsonl" ! -path "*/subagents/*" -type f \
    -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
}

# Collect planner session transcripts to TRANSCRIPT_DIR.
# Copies .jsonl files from Claude CLI projects directory, preserving UUID filenames.
# Returns 0 always: transcript collection is best-effort.
collect_planner_transcripts() {
  if ! mkdir -p "$TRANSCRIPT_DIR"; then
    warn "Failed to create transcript directory: $TRANSCRIPT_DIR"
    return 0
  fi

  local count=0
  while IFS= read -r tf; do
    local sid
    sid=$(basename "$tf" .jsonl)
    if [ -z "$sid" ] || [ "$sid" = ".jsonl" ]; then continue; fi

    if cp "$tf" "$TRANSCRIPT_DIR/$sid.jsonl" 2>/dev/null; then
      count=$((count + 1))
    else
      warn "Failed to copy planner transcript: $tf"
    fi
  done < <(_find_planner_transcripts)

  log "Planner transcripts collected ($count sessions)"
}
