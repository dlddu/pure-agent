#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for mock-agent entrypoint.sh

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

# ── export_config.json copy ──────────────────────────────────────────────────

@test "copies export_config.json from SCENARIO_DIR to WORK_DIR" {
  # Arrange
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"

  # Act
  run run_entrypoint
  [ "$status" -eq 0 ]

  # Assert
  [ -f "$WORK_DIR/export_config.json" ]
  run cat "$WORK_DIR/export_config.json"
  [[ "$output" == *"action"* ]]
}

@test "export_config.json content is preserved exactly after copy" {
  # Arrange
  local expected='{"action":"create_pr","branch":"feat/test"}'
  echo "$expected" > "$SCENARIO_DIR/export_config.json"

  # Act
  run_entrypoint

  # Assert
  local actual
  actual=$(cat "$WORK_DIR/export_config.json")
  [ "$actual" = "$expected" ]
}

# ── agent_result.txt handling ────────────────────────────────────────────────

@test "writes agent_result.txt content to /tmp/agent_result.txt" {
  # Arrange
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"
  echo "Task completed successfully." > "$SCENARIO_DIR/agent_result.txt"

  # Act
  run run_entrypoint
  [ "$status" -eq 0 ]

  # Assert
  [ -f "/tmp/agent_result.txt" ]
  run cat "/tmp/agent_result.txt"
  [[ "$output" == *"Task completed successfully."* ]]
}

@test "agent_result.txt content is preserved exactly" {
  # Arrange
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"
  local expected="Multiline result
line two
line three"
  echo "$expected" > "$SCENARIO_DIR/agent_result.txt"

  # Act
  run_entrypoint

  # Assert
  local actual
  actual=$(cat /tmp/agent_result.txt)
  [ "$actual" = "$expected" ]
}

# ── session_id.txt ───────────────────────────────────────────────────────────

@test "writes a dummy session ID to /tmp/session_id.txt" {
  # Arrange
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"

  # Act
  run run_entrypoint
  [ "$status" -eq 0 ]

  # Assert
  [ -f "/tmp/session_id.txt" ]
  local content
  content=$(cat /tmp/session_id.txt)
  [ -n "$content" ]
}

# ── missing fixture handling (depth-limit scenario) ──────────────────────────

@test "succeeds without export_config.json when fixture is absent" {
  # Arrange — SCENARIO_DIR is empty (no export_config.json)

  # Act
  run run_entrypoint

  # Assert — should not exit with error
  [ "$status" -eq 0 ]
}

@test "succeeds without agent_result.txt when fixture is absent" {
  # Arrange — only export_config present, agent_result absent
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"

  # Act
  run run_entrypoint

  # Assert
  [ "$status" -eq 0 ]
}

@test "writes default content to /tmp/agent_result.txt when agent_result fixture is missing" {
  # Arrange
  echo '{"action":"none"}' > "$SCENARIO_DIR/export_config.json"
  rm -f "$SCENARIO_DIR/agent_result.txt"

  # Act
  run run_entrypoint
  [ "$status" -eq 0 ]

  # Assert — file must exist (may be empty or contain a default)
  [ -f "/tmp/agent_result.txt" ]
}

# ── SCENARIO_DIR environment variable ────────────────────────────────────────

@test "fails when SCENARIO_DIR environment variable is not set" {
  # Arrange
  unset SCENARIO_DIR

  # Act
  run run_entrypoint

  # Assert
  [ "$status" -ne 0 ]
}
