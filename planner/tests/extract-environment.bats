#!/usr/bin/env bats
# Tests for extract-environment.jq filter
#
# The filter is used with `jq -rs` (slurp raw input).
# Input format: newline-delimited JSON objects (stream-json output).

FILTER="$BATS_TEST_DIRNAME/../extract-environment.jq"

@test "extracts result from result event" {
  result=$(echo '{"type":"result","result":"{\"environment_id\": \"default\"}"}' | jq -rs -f "$FILTER")
  [[ "$result" == *"environment_id"* ]]
  [[ "$result" == *"default"* ]]
}

@test "uses last result when multiple result events exist" {
  input=$(printf '%s\n%s' \
    '{"type":"result","result":"{\"environment_id\": \"default\"}"}' \
    '{"type":"result","result":"{\"environment_id\": \"infra\"}"}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [[ "$result" == *"infra"* ]]
}

@test "falls back to assistant text when no result event" {
  result=$(echo '{"type":"assistant","message":{"content":[{"type":"text","text":"{\"environment_id\": \"python-analysis\"}"}]}}' | jq -rs -f "$FILTER")
  [[ "$result" == *"python-analysis"* ]]
}

@test "concatenates multiple text blocks in assistant message" {
  result=$(echo '{"type":"assistant","message":{"content":[{"type":"text","text":"{\"environment_id\":"},{"type":"text","text":" \"infra\"}"}]}}' | jq -rs -f "$FILTER")
  [[ "$result" == *"infra"* ]]
}

@test "returns null when no matching events" {
  result=$(echo '{"type":"system","data":"init"}' | jq -rs -f "$FILTER")
  [ "$result" = "null" ]
}

@test "prefers result over assistant text" {
  input=$(printf '%s\n%s' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"{\"environment_id\": \"infra\"}"}]}}' \
    '{"type":"result","result":"{\"environment_id\": \"default\"}"}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [[ "$result" == *"default"* ]]
}

@test "skips result events with null result" {
  input=$(printf '%s\n%s' \
    '{"type":"result","result":null}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"{\"environment_id\": \"infra\"}"}]}}')
  result=$(echo "$input" | jq -rs -f "$FILTER")
  [[ "$result" == *"infra"* ]]
}
