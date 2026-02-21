#!/bin/bash
# Session transcript collection utilities.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

# Copy a session transcript and its subagent transcripts to TRANSCRIPT_DIR.
# Args: $1=transcript_file_path  $2=session_id
# Returns 0 always (warns on failure).
_copy_transcript() {
  local tf="${1:?_copy_transcript: missing transcript file argument}"
  local sid="${2:?_copy_transcript: missing session ID argument}"

  if [ ! -f "$tf" ]; then
    warn "Transcript file not found: $tf"
    return 0
  fi

  if ! cp "$tf" "$TRANSCRIPT_DIR/$sid.jsonl" 2>/dev/null; then
    warn "Failed to copy transcript: $tf"
  fi

  local subagent_dir
  subagent_dir="$(dirname "$tf")/$sid/subagents"
  if [ -d "$subagent_dir" ]; then
    mkdir -p "$TRANSCRIPT_DIR/$sid/subagents"
    if compgen -G "$subagent_dir/*" >/dev/null 2>&1; then
      cp "$subagent_dir"/* "$TRANSCRIPT_DIR/$sid/subagents/"
    fi
  fi
}

# List transcript files sorted by mtime (oldest first).
# Excludes subagent transcripts to prevent duplication.
_find_transcripts() {
  if [ ! -d "$CLAUDE_DIR/projects" ]; then
    warn "No projects directory found at $CLAUDE_DIR/projects"
    return 0
  fi
  find "$CLAUDE_DIR/projects" -name "*.jsonl" ! -path "*/subagents/*" -type f \
    -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
}

# Initialize the transcript output directory.
# Cleans any pre-existing content and sets a default session ID.
_init_transcript_dir() {
  if ! rm -rf "$TRANSCRIPT_DIR"; then
    warn "Failed to clean transcript directory: $TRANSCRIPT_DIR"
  fi
  if ! mkdir -p "$TRANSCRIPT_DIR"; then
    warn "Failed to create transcript directory: $TRANSCRIPT_DIR"
    return 0
  fi
  if ! echo "unknown" > "$SESSION_ID_FILE"; then
    warn "Failed to write default session ID"
  fi
}

# Orchestrate transcript collection: find, copy, and set session ID.
# The last transcript (by mtime) determines the current session ID.
# Returns 0 always: transcript collection is best-effort so the agent
# pipeline continues even if transcripts cannot be gathered.
collect_transcripts() {
  _init_transcript_dir

  local count=0 last_sid="" sid
  while IFS= read -r tf; do
    sid=$(basename "$tf" .jsonl)
    if [ -z "$sid" ] || [ "$sid" = ".jsonl" ]; then continue; fi

    _copy_transcript "$tf" "$sid"
    last_sid="$sid"
    count=$((count + 1))
  done < <(_find_transcripts)

  # _find_transcripts는 mtime 오름차순 정렬. 마지막 항목이 가장 최근 세션.
  if [ -n "$last_sid" ]; then
    echo "$last_sid" > "$SESSION_ID_FILE"
  fi

  if [ "$count" -gt 1 ]; then
    warn "Multiple sessions found ($count); using most recent"
  fi
  log "Transcripts collected ($count sessions)"
}
