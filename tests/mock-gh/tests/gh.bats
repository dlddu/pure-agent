#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for mock-gh script

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

# ── gh pr create ─────────────────────────────────────────────────────────────

@test "gh pr create: exits with code 0" {
  run run_mock_gh pr create --title "My PR" --body "body" --base main
  [ "$status" -eq 0 ]
}

@test "gh pr create: outputs a fake PR URL" {
  run run_mock_gh pr create --title "My PR" --body "body" --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://"* ]]
  [[ "$output" == *"/pull/"* ]]
}

@test "gh pr create: records call arguments to a file" {
  run run_mock_gh pr create --title "Test PR" --body "PR body" --base main

  # A call record file must have been written
  local record_count
  record_count=$(ls "$GH_CALLS_DIR" 2>/dev/null | wc -l)
  [ "$record_count" -gt 0 ]
}

@test "gh pr create: recorded file contains the --title argument" {
  run_mock_gh pr create --title "Feature title" --body "body" --base main

  local record_file
  record_file=$(ls "$GH_CALLS_DIR" | head -1)
  run cat "$GH_CALLS_DIR/$record_file"
  [[ "$output" == *"Feature title"* ]]
}

@test "gh pr create: recorded file contains the --body argument" {
  run_mock_gh pr create --title "Title" --body "Detailed PR body" --base main

  local record_file
  record_file=$(ls "$GH_CALLS_DIR" | head -1)
  run cat "$GH_CALLS_DIR/$record_file"
  [[ "$output" == *"Detailed PR body"* ]]
}

@test "gh pr create: each invocation creates a separate record file" {
  run_mock_gh pr create --title "PR 1" --body "body" --base main
  run_mock_gh pr create --title "PR 2" --body "body" --base main

  local record_count
  record_count=$(ls "$GH_CALLS_DIR" | wc -l)
  [ "$record_count" -eq 2 ]
}

# ── gh auth status ────────────────────────────────────────────────────────────

@test "gh auth status: exits with code 0" {
  run run_mock_gh auth status
  [ "$status" -eq 0 ]
}

@test "gh auth status: produces non-empty output" {
  run run_mock_gh auth status
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ── gh api repos/... ──────────────────────────────────────────────────────────

@test "gh api repos call: exits with code 0" {
  run run_mock_gh api repos/myorg/myrepo
  [ "$status" -eq 0 ]
}

@test "gh api repos call: returns JSON with push permission true" {
  run run_mock_gh api repos/myorg/myrepo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"push"'* ]]
  [[ "$output" == *'true'* ]]
}

@test "gh api repos call: response is valid JSON" {
  run run_mock_gh api repos/myorg/myrepo
  [ "$status" -eq 0 ]
  echo "$output" | jq . > /dev/null
}

@test "gh api repos call: permissions object contains push key" {
  run run_mock_gh api repos/myorg/myrepo
  local push_value
  push_value=$(echo "$output" | jq '.permissions.push')
  [ "$push_value" = "true" ]
}

# ── unknown commands ──────────────────────────────────────────────────────────

@test "unknown top-level command: exits with non-zero code" {
  run run_mock_gh totally-unknown-command
  [ "$status" -ne 0 ]
}

@test "unknown subcommand under known group: exits with non-zero code" {
  run run_mock_gh pr unknown-subcommand
  [ "$status" -ne 0 ]
}

@test "unknown command: outputs an error message" {
  run run_mock_gh totally-unknown-command
  [ -n "$output" ]
}
