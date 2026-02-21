#!/usr/bin/env bats
# Tests for lib/transcripts.sh: _copy_transcript, _find_transcripts,
#   _init_transcript_dir, collect_transcripts

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants transcripts; }

# ── _copy_transcript ─────────────────────────────────────────

@test "_copy_transcript: copies transcript file to destination" {
  _load
  mkdir -p "$TRANSCRIPT_DIR" "$BATS_TEST_TMPDIR/src"
  echo '{"line":1}' > "$BATS_TEST_TMPDIR/src/sess1.jsonl"
  _copy_transcript "$BATS_TEST_TMPDIR/src/sess1.jsonl" "sess1" 2>/dev/null
  [ -f "$TRANSCRIPT_DIR/sess1.jsonl" ]
  [ "$(cat "$TRANSCRIPT_DIR/sess1.jsonl")" = '{"line":1}' ]
}

@test "_copy_transcript: copies subagent transcripts when present" {
  _load
  mkdir -p "$TRANSCRIPT_DIR" "$BATS_TEST_TMPDIR/src/sess1/subagents"
  echo '{}' > "$BATS_TEST_TMPDIR/src/sess1.jsonl"
  echo '{"sub":true}' > "$BATS_TEST_TMPDIR/src/sess1/subagents/sub1.jsonl"
  _copy_transcript "$BATS_TEST_TMPDIR/src/sess1.jsonl" "sess1" 2>/dev/null
  [ -f "$TRANSCRIPT_DIR/sess1/subagents/sub1.jsonl" ]
}

@test "_copy_transcript: warns when source file is missing" {
  _load
  mkdir -p "$TRANSCRIPT_DIR"
  run _copy_transcript "/nonexistent/path.jsonl" "nosess"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Transcript file not found"* ]]
}

@test "_copy_transcript: skips subagents when directory absent" {
  _load
  mkdir -p "$TRANSCRIPT_DIR" "$BATS_TEST_TMPDIR/src"
  echo '{}' > "$BATS_TEST_TMPDIR/src/sess2.jsonl"
  _copy_transcript "$BATS_TEST_TMPDIR/src/sess2.jsonl" "sess2" 2>/dev/null
  [ ! -d "$TRANSCRIPT_DIR/sess2/subagents" ]
}

@test "_copy_transcript: fails when called without arguments" {
  _load
  mkdir -p "$TRANSCRIPT_DIR"
  run _copy_transcript
  [ "$status" -ne 0 ]
}

@test "_copy_transcript: fails when session ID is missing" {
  _load
  mkdir -p "$TRANSCRIPT_DIR" "$BATS_TEST_TMPDIR/src"
  echo '{}' > "$BATS_TEST_TMPDIR/src/sess.jsonl"
  run _copy_transcript "$BATS_TEST_TMPDIR/src/sess.jsonl"
  [ "$status" -ne 0 ]
}

# ── _find_transcripts ────────────────────────────────────────

@test "_find_transcripts: warns when projects directory is missing" {
  _load
  rm -rf "$CLAUDE_DIR/projects"
  run _find_transcripts
  [ "$status" -eq 0 ]
  [[ "$output" == *"No projects directory"* ]]
}

@test "_find_transcripts: returns files sorted by mtime" {
  _load
  local projects_dir="$CLAUDE_DIR/projects/test"
  mkdir -p "$projects_dir"

  echo '{}' > "$projects_dir/session-a.jsonl"
  sleep 0.1
  echo '{}' > "$projects_dir/session-b.jsonl"

  result="$(_find_transcripts 2>/dev/null)"
  first_line=$(echo "$result" | head -1)
  last_line=$(echo "$result" | tail -1)
  [[ "$first_line" == *"session-a.jsonl" ]]
  [[ "$last_line" == *"session-b.jsonl" ]]
}

@test "_find_transcripts: excludes subagent transcripts" {
  _load
  local projects_dir="$CLAUDE_DIR/projects/test"
  mkdir -p "$projects_dir/sid/subagents"

  echo '{}' > "$projects_dir/main.jsonl"
  echo '{}' > "$projects_dir/sid/subagents/sub.jsonl"

  result="$(_find_transcripts 2>/dev/null)"
  [[ "$result" == *"main.jsonl"* ]]
  [[ "$result" != *"sub.jsonl"* ]]
}

@test "_find_transcripts: returns empty on empty projects directory" {
  _load
  mkdir -p "$CLAUDE_DIR/projects"
  result="$(_find_transcripts 2>/dev/null)"
  [ -z "$result" ]
}

@test "_find_transcripts: finds transcripts in nested directories" {
  _load
  local nested_dir="$CLAUDE_DIR/projects/org/repo"
  mkdir -p "$nested_dir"
  echo '{}' > "$nested_dir/deep-session.jsonl"

  result="$(_find_transcripts 2>/dev/null)"
  [[ "$result" == *"deep-session.jsonl"* ]]
}

# ── _init_transcript_dir ────────────────────────────────────

@test "_init_transcript_dir: creates directory and default session ID" {
  _load
  _init_transcript_dir 2>/dev/null
  [ -d "$TRANSCRIPT_DIR" ]
  [ "$(cat "$SESSION_ID_FILE")" = "unknown" ]
}

@test "_init_transcript_dir: cleans pre-existing content" {
  _load
  mkdir -p "$TRANSCRIPT_DIR"
  echo "stale" > "$TRANSCRIPT_DIR/old.jsonl"
  _init_transcript_dir 2>/dev/null
  [ ! -f "$TRANSCRIPT_DIR/old.jsonl" ]
  [ -d "$TRANSCRIPT_DIR" ]
}

@test "_init_transcript_dir: succeeds when transcript dir does not exist yet" {
  _load
  rm -rf "$TRANSCRIPT_DIR"
  _init_transcript_dir 2>/dev/null
  [ -d "$TRANSCRIPT_DIR" ]
  [ "$(cat "$SESSION_ID_FILE")" = "unknown" ]
}

# ── collect_transcripts ──────────────────────────────────────

@test "collect_transcripts: sets session ID from transcript filename" {
  _load
  local projects_dir="$CLAUDE_DIR/projects/test"
  mkdir -p "$projects_dir"
  echo '{}' > "$projects_dir/my-session-id.jsonl"

  run collect_transcripts
  [ "$status" -eq 0 ]
  [[ "$output" == *"Transcripts collected (1 sessions)"* ]]
  [ "$(cat "$SESSION_ID_FILE")" = "my-session-id" ]
}

@test "collect_transcripts: copies transcripts to TRANSCRIPT_DIR" {
  _load
  local projects_dir="$CLAUDE_DIR/projects/test"
  mkdir -p "$projects_dir"
  echo '{"data":"test"}' > "$projects_dir/abc123.jsonl"

  collect_transcripts 2>/dev/null
  [ -f "$TRANSCRIPT_DIR/abc123.jsonl" ]
  [ "$(cat "$TRANSCRIPT_DIR/abc123.jsonl")" = '{"data":"test"}' ]
}

@test "collect_transcripts: writes 'unknown' when no transcripts found" {
  _load
  mkdir -p "$CLAUDE_DIR/projects"
  run collect_transcripts
  [ "$status" -eq 0 ]
  [[ "$output" == *"Transcripts collected (0 sessions)"* ]]
  [ "$(cat "$SESSION_ID_FILE")" = "unknown" ]
}

@test "collect_transcripts: picks most recent session ID with multiple sessions" {
  _load
  local projects_dir="$CLAUDE_DIR/projects/test"
  mkdir -p "$projects_dir"

  echo '{}' > "$projects_dir/session-old.jsonl"
  sleep 0.1
  echo '{}' > "$projects_dir/session-new.jsonl"

  run collect_transcripts
  [ "$status" -eq 0 ]
  [[ "$output" == *"Multiple sessions found (2)"* ]]
  [[ "$output" == *"using most recent"* ]]
  [ "$(cat "$SESSION_ID_FILE")" = "session-new" ]
}
