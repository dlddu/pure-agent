#!/usr/bin/env bats
# Unit tests for lib/ modules (independent sourcing)

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

# ── logging.sh ──────────────────────────────────────────────

@test "logging.sh: log writes to stderr" {
  source "$LIB_DIR/logging.sh"
  run log "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[entrypoint] test message"* ]]
}

@test "logging.sh: warn includes WARN prefix" {
  source "$LIB_DIR/logging.sh"
  run warn "warning message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: warning message"* ]]
}

@test "logging.sh: die exits with code 1" {
  source "$LIB_DIR/logging.sh"
  run die "fatal error"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: fatal error"* ]]
}

# ── constants.sh ────────────────────────────────────────────

@test "constants.sh: external contract paths are set" {
  source "$LIB_DIR/logging.sh"
  source "$LIB_DIR/constants.sh"
  [ -n "$WORK_DIR" ]
  [ -n "$TRANSCRIPT_DIR" ]
  [ -n "$AGENT_OUTPUT_COPY" ]
  [ -n "$RESULT_FILE" ]
  [ -n "$SESSION_ID_FILE" ]
}

@test "constants.sh: PARSE_FAILED_RESULT matches jq filter value" {
  source "$LIB_DIR/logging.sh"
  source "$LIB_DIR/constants.sh"
  [ "$PARSE_FAILED_RESULT" = "Output not parseable" ]
  # Verify it matches the jq filter fallback
  jq_fallback=$(echo "" | jq -rs -f "$EXTRACT_RESULT_FILTER")
  [ "$PARSE_FAILED_RESULT" = "$jq_fallback" ]
}

@test "constants.sh: TRANSCRIPT_DIR is under WORK_DIR" {
  source "$LIB_DIR/logging.sh"
  source "$LIB_DIR/constants.sh"
  [[ "$TRANSCRIPT_DIR" == "$WORK_DIR"* ]]
}

@test "shared/defaults.sh: DEFAULT_WORK_DIR is /work" {
  source "$BATS_TEST_DIRNAME/../shared/defaults.sh"
  [ "$DEFAULT_WORK_DIR" = "/work" ]
}
