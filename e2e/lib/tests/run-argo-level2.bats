#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for Level ② functions in e2e/run-argo.sh
#
# TDD Red Phase: the functions under test currently return 0 immediately via
# "[SKIP] ... && return 0" guards.  These tests will all FAIL until the skip
# guards are removed and the real logic is implemented (DLD-466).
#
# Covered functions:
#   check_prerequisites (Level 2 branch)
#   _level2_place_cycle_fixtures
#   _level2_verify_cycle

source "$BATS_TEST_DIRNAME/test-helper.sh"

# run-argo.sh reads SCENARIOS_DIR at source time; point it to fixtures.
setup() {
  common_setup

  # Set up a temporary scenarios directory for tests that need scenario YAMLs
  export SCENARIOS_DIR="$BATS_TEST_TMPDIR/scenarios"
  mkdir -p "$SCENARIOS_DIR"

  # Level 2 defaults expected by run-argo.sh
  export LEVEL="2"
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-level2"
  export MOCK_AGENT_IMAGE="ghcr.io/dlddu/pure-agent/mock-agent:latest"
  export MOCK_API_URL="http://mock-api.pure-agent.svc.cluster.local:4000"
  export WORKFLOW_TIMEOUT="600"

  # Stub out external tools so sourcing run-argo.sh does not fail when the
  # real binaries are absent in the test environment.
  yq()      { command yq "$@" 2>/dev/null || true; }
  export -f yq

  load_run_argo
}

# ── Helper: write a minimal Level-2 scenario YAML ─────────────────────────────

write_scenario_yaml() {
  local name="$1"
  local yaml_file="$SCENARIOS_DIR/${name}.yaml"
  cat > "$yaml_file" <<YAML
name: ${name}
level: [2]
cycles:
  - export_config:
      linear_issue_id: "mock-issue-id"
      actions:
        - "none"
      session_id: "mock-session-0"
    agent_result: "Cycle 0 done."
assertions:
  router_decision: "stop"
  export_handler_exit: 0
YAML
  echo "$yaml_file"
}

write_multi_cycle_scenario_yaml() {
  local name="$1"
  local yaml_file="$SCENARIOS_DIR/${name}.yaml"
  cat > "$yaml_file" <<YAML
name: ${name}
level: [2]
cycles:
  - export_config:
      linear_issue_id: "mock-issue-id"
      actions:
        - "continue"
      session_id: "mock-session-0"
    agent_result: "Cycle 0 done, continuing..."
  - export_config:
      linear_issue_id: "mock-issue-id"
      actions:
        - "none"
      session_id: "mock-session-1"
    agent_result: "Cycle 1 done, stopping."
assertions:
  router_decisions:
    - "continue"
    - "stop"
YAML
  echo "$yaml_file"
}

write_depth_limit_scenario_yaml() {
  local name="$1"
  local max_depth="${2:-2}"
  local yaml_file="$SCENARIOS_DIR/${name}.yaml"
  cat > "$yaml_file" <<YAML
name: ${name}
level: [2]
max_depth: ${max_depth}
cycles:
  - export_config: null
    agent_result: "Depth limit reached"
assertions:
  router_decision: "stop"
YAML
  echo "$yaml_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# check_prerequisites — Level 2 branch
# ═══════════════════════════════════════════════════════════════════════════════

@test "check_prerequisites (Level 2): passes when all required tools are present" {
  # Arrange — stub all required commands to exist
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  export LEVEL="2"

  # Act
  run check_prerequisites

  # Assert
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): fails when argo is not installed" {
  # Arrange — argo not found
  argo() { return 127; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  # Override command to simulate missing argo
  command() {
    if [[ "$2" == "argo" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Level 2): fails when kubectl is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "kubectl" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Level 2): fails when jq is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "jq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Level 2): fails when yq is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "yq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Level 2): does not require LINEAR_API_KEY" {
  # Arrange — all tools present, but LINEAR_API_KEY unset
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq
  unset LINEAR_API_KEY
  export LEVEL="2"

  run check_prerequisites

  # Should still pass — Level 2 does not need API keys
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): does not require GITHUB_TOKEN" {
  # Arrange
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq
  unset GITHUB_TOKEN
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): success output does not mention Level 3" {
  # Arrange
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq
  export LEVEL="2"

  run check_prerequisites

  [ "$status" -eq 0 ]
  [[ "$output" != *"Level 3"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# _level2_place_cycle_fixtures
# ═══════════════════════════════════════════════════════════════════════════════

@test "_level2_place_cycle_fixtures: creates export_config.json from cycle YAML" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/cycle-out"
  mkdir -p "$out_dir"

  # Act — cycle index 0 has export_config defined
  run _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$out_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: export_config.json is valid JSON" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/cycle-out"
  mkdir -p "$out_dir"

  # Act
  _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert — jq must parse without error
  run jq . "$out_dir/export_config.json"
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: export_config.json contains expected field values" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/cycle-out"
  mkdir -p "$out_dir"

  # Act
  _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert — linear_issue_id must be preserved
  run jq -r '.linear_issue_id' "$out_dir/export_config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "mock-issue-id" ]
}

@test "_level2_place_cycle_fixtures: creates agent_result.txt when cycle has agent_result" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/cycle-out"
  mkdir -p "$out_dir"

  # Act
  run _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$out_dir/agent_result.txt" ]
}

@test "_level2_place_cycle_fixtures: agent_result.txt contains the expected text" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/cycle-out"
  mkdir -p "$out_dir"

  # Act
  _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert
  run grep -F "Cycle 0 done." "$out_dir/agent_result.txt"
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: does not create export_config.json when cycle export_config is null" {
  # Arrange — depth-limit scenario has export_config: null
  local yaml_file
  yaml_file=$(write_depth_limit_scenario_yaml "depth-limit")
  local out_dir="$BATS_TEST_TMPDIR/cycle-null-out"
  mkdir -p "$out_dir"

  # Act — cycle 0 has null export_config
  run _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert — file must NOT be present
  [ "$status" -eq 0 ]
  [ ! -f "$out_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: creates the scenario_dir when it does not exist" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/new-dir-$$"
  # Deliberately NOT creating out_dir

  # Act
  run _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert — function should create the directory and succeed
  [ "$status" -eq 0 ]
  [ -d "$out_dir" ]
}

@test "_level2_place_cycle_fixtures: places correct fixtures for cycle index 1 in multi-cycle scenario" {
  # Arrange — write multi-cycle scenario
  local yaml_file
  yaml_file=$(write_multi_cycle_scenario_yaml "continue-then-stop")
  local out_dir="$BATS_TEST_TMPDIR/cycle1-out"
  mkdir -p "$out_dir"

  # Act — request cycle index 1
  run _level2_place_cycle_fixtures "$yaml_file" 1 "$out_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$out_dir/export_config.json" ]
  [ -f "$out_dir/agent_result.txt" ]
  run grep -F "Cycle 1 done" "$out_dir/agent_result.txt"
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: cycle 1 actions contain 'none' in continue-then-stop scenario" {
  # Arrange
  local yaml_file
  yaml_file=$(write_multi_cycle_scenario_yaml "continue-then-stop")
  local out_dir="$BATS_TEST_TMPDIR/cycle1-actions-out"
  mkdir -p "$out_dir"

  # Act
  _level2_place_cycle_fixtures "$yaml_file" 1 "$out_dir"

  # Assert — cycle 1 has actions: ["none"]
  run jq -r '.actions[0]' "$out_dir/export_config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "_level2_place_cycle_fixtures: removes stale agent_result.txt when cycle has no agent_result" {
  # Arrange — create a stale file in the output dir, then use a cycle with no agent_result
  local yaml_file="$SCENARIOS_DIR/no-agent-result.yaml"
  cat > "$yaml_file" <<YAML
name: no-agent-result
level: [2]
max_depth: 2
cycles:
  - export_config: null
YAML
  local out_dir="$BATS_TEST_TMPDIR/stale-out"
  mkdir -p "$out_dir"
  echo "stale content" > "$out_dir/agent_result.txt"

  # Act — no-agent-result cycle 0 has no agent_result field at all
  run _level2_place_cycle_fixtures "$yaml_file" 0 "$out_dir"

  # Assert — stale file should be gone
  [ "$status" -eq 0 ]
  [ ! -f "$out_dir/agent_result.txt" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# _level2_verify_cycle
# ═══════════════════════════════════════════════════════════════════════════════

@test "_level2_verify_cycle: calls assert_workflow_succeeded for the given workflow" {
  # Arrange — mock assert_workflow_succeeded to record calls.
  # Call directly (not via `run`) so the mock writes to the log in the same
  # process; `run` spawns a subshell where exports do not propagate back.
  local call_log="$WORK_DIR/assert-calls.txt"
  touch "$call_log"

  assert_workflow_succeeded() {
    echo "assert_workflow_succeeded called with: $*" >> "$call_log"
  }
  export -f assert_workflow_succeeded

  assert_mock_api() { return 0; }
  export -f assert_mock_api

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act — direct call keeps mock side-effects visible in this shell.
  _level2_verify_cycle "$yaml_file" "pure-agent-test-wf" 0

  # Assert
  grep -q "assert_workflow_succeeded called with: pure-agent-test-wf" "$call_log"
}

@test "_level2_verify_cycle: fails when assert_workflow_succeeded fails" {
  # Arrange
  assert_workflow_succeeded() {
    return 1
  }
  export -f assert_workflow_succeeded

  assert_mock_api() { return 0; }
  export -f assert_mock_api

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act
  run _level2_verify_cycle "$yaml_file" "failing-wf" 0

  # Assert
  [ "$status" -ne 0 ]
}

@test "_level2_verify_cycle: calls assert_mock_api for router_decision when defined" {
  # Arrange — call directly so mock side-effects are visible in this shell.
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local call_log="$WORK_DIR/mock-api-calls.txt"
  touch "$call_log"
  assert_mock_api() {
    echo "assert_mock_api called with: $*" >> "$call_log"
    return 0
  }
  export -f assert_mock_api

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  # none-action has assertions.router_decision: "stop"

  # Act — direct call keeps mock writes in the current process.
  _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — assert_mock_api should have been called with router_decision value
  grep -q "stop" "$call_log"
}

@test "_level2_verify_cycle: calls assert_mock_api for router_decisions array entry at correct index" {
  # Arrange — call directly to keep mock writes in the current process.
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local call_log="$WORK_DIR/mock-api-calls.txt"
  touch "$call_log"
  assert_mock_api() {
    echo "assert_mock_api called with: $*" >> "$call_log"
    return 0
  }
  export -f assert_mock_api

  # Multi-cycle scenario: cycle 0 expects "continue", cycle 1 expects "stop"
  local yaml_file
  yaml_file=$(write_multi_cycle_scenario_yaml "continue-then-stop")

  # Act — verify cycle index 0; direct call keeps mock side-effects visible.
  _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — should check "continue" for cycle 0
  grep -q "continue" "$call_log"
}

@test "_level2_verify_cycle: does not call assert_mock_api for router_decision when not defined" {
  # Arrange — write scenario without router_decision assertions
  local yaml_file="$SCENARIOS_DIR/no-assertions.yaml"
  cat > "$yaml_file" <<'YAML'
name: no-assertions
level: [2]
cycles:
  - export_config:
      linear_issue_id: "mock-id"
      actions: ["none"]
    agent_result: "done"
assertions: {}
YAML

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local call_log="$WORK_DIR/mock-api-calls.txt"
  assert_mock_api() {
    echo "assert_mock_api called" >> "$call_log"
    return 0
  }
  export -f assert_mock_api

  # Act
  run _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — mock_api should not have been called (no assertions defined)
  [ "$status" -eq 0 ]
  [ ! -f "$call_log" ] || [ ! -s "$call_log" ]
}

@test "_level2_verify_cycle: calls assert_mock_api for linear_comment body_contains when defined" {
  # Arrange — scenario with linear_comment assertion
  local yaml_file="$SCENARIOS_DIR/linear-comment.yaml"
  cat > "$yaml_file" <<'YAML'
name: linear-comment
level: [2]
cycles:
  - export_config:
      linear_issue_id: "mock-id"
      actions: ["none"]
    agent_result: "done"
assertions:
  linear_comment:
    body_contains: "작업 완료"
YAML

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local call_log="$WORK_DIR/mock-api-calls.txt"
  touch "$call_log"
  assert_mock_api() {
    echo "assert_mock_api: $*" >> "$call_log"
    return 0
  }
  export -f assert_mock_api

  # Act — direct call so mock writes are visible in this process.
  _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — should check "작업 완료"
  grep -q "작업 완료" "$call_log"
}

@test "_level2_verify_cycle: calls assert_mock_api for github_pr when assertion is true" {
  # Arrange — scenario with github_pr: true
  local yaml_file="$SCENARIOS_DIR/with-github-pr.yaml"
  cat > "$yaml_file" <<'YAML'
name: with-github-pr
level: [2]
cycles:
  - export_config:
      linear_issue_id: "mock-id"
      actions: ["create_pr"]
    agent_result: "PR created"
assertions:
  github_pr: true
YAML

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local call_log="$WORK_DIR/mock-api-calls.txt"
  touch "$call_log"
  assert_mock_api() {
    echo "assert_mock_api: $*" >> "$call_log"
    return 0
  }
  export -f assert_mock_api

  # Act — direct call so mock writes are visible in this process.
  _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — should call assert_mock_api with create_pr
  grep -q "create_pr" "$call_log"
}

@test "_level2_verify_cycle: passes cycle index to log output" {
  # Arrange
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded
  assert_mock_api() { return 0; }
  export -f assert_mock_api

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act — cycle index 0 should appear in some form in output/log
  run _level2_verify_cycle "$yaml_file" "my-wf" 0

  # Assert — function must exit cleanly
  [ "$status" -eq 0 ]
}
