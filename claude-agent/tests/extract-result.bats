#!/usr/bin/env bats
# Tests for extract-result.jq filter
#
# The filter is used with `jq -rs` (slurp raw input).
# Input format: newline-delimited JSON objects (stream-json output).
# jq -s reads all lines and wraps them into a single array.

FILTER="$BATS_TEST_DIRNAME/../extract-result.jq"

@test "extracts result from result event" {
  result=$(echo '{"type":"result","result":"Task completed"}' | jq -rs -f "$FILTER")
  [ "$result" = "Task completed" ]
}

@test "uses last result when multiple result events exist" {
  input=$(printf '%s\n%s' \
    '{"type":"result","result":"First"}' \
    '{"type":"result","result":"Second"}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [ "$result" = "Second" ]
}

@test "falls back to assistant text when no result event" {
  result=$(echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world"}]}}' | jq -rs -f "$FILTER")
  [ "$result" = "Hello world" ]
}

@test "concatenates multiple text blocks in assistant message" {
  result=$(echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}]}}' | jq -rs -f "$FILTER")
  [ "$result" = "Hello world" ]
}

@test "uses last non-empty assistant message" {
  input=$(printf '%s\n%s' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"First"}]}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Last"}]}}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [ "$result" = "Last" ]
}

@test "returns default when no matching events" {
  result=$(echo '{"type":"system","data":"init"}' | jq -rs -f "$FILTER")
  [ "$result" = "Output not parseable" ]
}

@test "prefers result over assistant text" {
  input=$(printf '%s\n%s' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Chat text"}]}}' \
    '{"type":"result","result":"Final result"}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [ "$result" = "Final result" ]
}

@test "skips result events with null result" {
  input=$(printf '%s\n%s' \
    '{"type":"result","result":null}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Fallback"}]}}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [ "$result" = "Fallback" ]
}
