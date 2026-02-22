#!/usr/bin/env bash
# e2e/lib/assertions.sh — assertion helpers for e2e tests.
#
# Usage in BATS: source this file with --source-only to load functions only.
# Direct execution prints usage.
#
# Functions:
#   assert_router_decision <expected>
#   assert_exit_code <expected> <actual>
#   assert_mock_api <type> <expected_body_contains>
#   assert_file_exists <path>
#   assert_file_contains <path> <expected>

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  # Being sourced for function definitions only — skip the rest of this file.
  true
fi

# ── assert_exit_code ──────────────────────────────────────────────────────────

assert_exit_code() {
  local expected="$1"
  local actual="$2"

  if [ "$expected" != "$actual" ]; then
    echo "FAIL assert_exit_code: expected exit code '$expected' but got '$actual'" >&2
    return 1
  fi
}

# ── assert_file_exists ────────────────────────────────────────────────────────

assert_file_exists() {
  local path="$1"

  if [ ! -f "$path" ]; then
    echo "FAIL assert_file_exists: file not found: '$path'" >&2
    return 1
  fi
}

# ── assert_file_contains ──────────────────────────────────────────────────────

assert_file_contains() {
  local path="$1"
  local expected="$2"

  if [ ! -f "$path" ]; then
    echo "FAIL assert_file_contains: file not found: '$path'" >&2
    return 1
  fi

  if ! grep -qF "$expected" "$path"; then
    echo "FAIL assert_file_contains: file '$path' does not contain '$expected'" >&2
    return 1
  fi
}

# ── assert_router_decision ────────────────────────────────────────────────────
# Reads the router output file pointed to by ROUTER_OUTPUT and verifies the
# decision matches the expected value.

assert_router_decision() {
  local expected="$1"
  local router_file="${ROUTER_OUTPUT:-}"

  if [ -z "$router_file" ]; then
    echo "FAIL assert_router_decision: ROUTER_OUTPUT env var is not set" >&2
    return 1
  fi

  if [ ! -f "$router_file" ]; then
    echo "FAIL assert_router_decision: router output file not found: '$router_file'" >&2
    return 1
  fi

  local actual
  actual=$(cat "$router_file")

  if [ "$expected" != "$actual" ]; then
    echo "FAIL assert_router_decision: expected decision '$expected' but got '$actual'" >&2
    return 1
  fi
}

# ── assert_mock_api ───────────────────────────────────────────────────────────
# Queries GET /assertions on the mock-api server and checks that at least one
# recorded call matches the given type and contains the expected body string.
#
# Arguments:
#   $1  type                   — "mutation" or "query"
#   $2  expected_body_contains — substring that must appear in the call's body JSON

assert_mock_api() {
  local type="$1"
  local expected_body_contains="$2"
  local base_url="${MOCK_API_URL:-http://localhost:4000}"

  local response
  response=$(curl -sf "${base_url}/assertions") || {
    echo "FAIL assert_mock_api: could not reach mock-api at ${base_url}/assertions" >&2
    return 1
  }

  # Check that at least one call matches type AND (operationName or body) substring.
  # The operationName field is checked first for convenience; body JSON string is
  # also searched so callers can assert on arbitrary payload content.
  local match
  match=$(echo "$response" | jq --arg t "$type" --arg b "$expected_body_contains" \
    '[.calls[] | select(
        .type == $t and
        ((.operationName // "" | contains($b)) or ((.body | tostring) | contains($b)))
     )] | length')

  if [ "$match" -eq 0 ]; then
    echo "FAIL assert_mock_api: no recorded '$type' call with body containing '$expected_body_contains'" >&2
    echo "Recorded calls: $response" >&2
    return 1
  fi
}
