#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for Integration functions in tests/run-integration.sh
#
# TDD Red Phase: the functions under test currently return 0 immediately via
# "[SKIP] ... && return 0" guards.  These tests will all FAIL until the skip
# guards are removed and the real logic is implemented (DLD-466).
#
# Covered functions:
#   check_prerequisites
#   prepare_run_fixtures (from lib/common.sh)
#   verify_run

source "$BATS_TEST_DIRNAME/test-helper.sh"

# run-integration.sh reads SCENARIOS_DIR at source time; point it to fixtures.
setup() {
  common_setup

  # Set up a temporary scenarios directory for tests that need scenario YAMLs
  export SCENARIOS_DIR="$BATS_TEST_TMPDIR/scenarios"
  mkdir -p "$SCENARIOS_DIR"

  # Integration defaults expected by run-integration.sh
  export LEVEL="integration"
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-integration"
  export MOCK_AGENT_IMAGE="ghcr.io/dlddu/pure-agent/mock-agent:latest"
  export MOCK_API_URL="http://mock-api.pure-agent.svc.cluster.local:4000"
  export WORKFLOW_TIMEOUT="600"

  # Stub out external tools so sourcing run-integration.sh does not fail when the
  # real binaries are absent in the test environment.
  yq()      { command yq "$@" 2>/dev/null || true; }
  export -f yq

  load_run_argo
}

# ── Helper: write a minimal Integration scenario YAML ─────────────────────────────

write_scenario_yaml() {
  local name="$1"
  local yaml_file="$SCENARIOS_DIR/${name}.yaml"
  cat > "$yaml_file" <<YAML
name: ${name}
level: [integration]
run:
  export_config:
    summary: "mock summary"
    actions:
      - "none"
    session_id: "mock-session-0"
  agent_result: "Run done."
assertions:
  export_handler_exit: 0
YAML
  echo "$yaml_file"
}

write_null_config_scenario_yaml() {
  local name="$1"
  local yaml_file="$SCENARIOS_DIR/${name}.yaml"
  cat > "$yaml_file" <<YAML
name: ${name}
level: [integration]
run:
  export_config: null
  agent_result: "No export config produced"
assertions:
  export_handler_exit: 0
YAML
  echo "$yaml_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# check_prerequisites — Integration branch
# ═══════════════════════════════════════════════════════════════════════════════

@test "check_prerequisites (Integration): passes when all required tools are present" {
  # Arrange — stub all required commands to exist
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  export LEVEL="integration"

  # Act
  run check_prerequisites

  # Assert
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Integration): fails when argo is not installed" {
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
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Integration): fails when kubectl is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "kubectl" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Integration): fails when jq is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "jq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Integration): fails when yq is not installed" {
  # Arrange
  command() {
    if [[ "$2" == "yq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Integration): does not require GITHUB_TOKEN" {
  # Arrange
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq
  unset GITHUB_TOKEN
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Integration): success output does not mention E2E" {
  # Arrange
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq
  export LEVEL="integration"

  run check_prerequisites

  [ "$status" -eq 0 ]
  [[ "$output" != *"E2E"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# prepare_run_fixtures (from lib/common.sh)
# ═══════════════════════════════════════════════════════════════════════════════

@test "prepare_run_fixtures: creates export_config.json from run YAML" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/run-out"
  mkdir -p "$out_dir"

  # Act — run has export_config defined
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$out_dir/export_config.json" ]
}

@test "prepare_run_fixtures: export_config.json is valid JSON" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/run-out"
  mkdir -p "$out_dir"

  # Act
  prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — jq must parse without error
  run jq . "$out_dir/export_config.json"
  [ "$status" -eq 0 ]
}

@test "prepare_run_fixtures: export_config.json contains expected field values" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/run-out"
  mkdir -p "$out_dir"

  # Act
  prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — summary must be preserved
  run jq -r '.summary' "$out_dir/export_config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "mock summary" ]
}

@test "prepare_run_fixtures: creates agent_result.txt when run has agent_result" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/run-out"
  mkdir -p "$out_dir"

  # Act
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$out_dir/agent_result.txt" ]
}

@test "prepare_run_fixtures: agent_result.txt contains the expected text" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/run-out"
  mkdir -p "$out_dir"

  # Act
  prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert
  run grep -F "Run done." "$out_dir/agent_result.txt"
  [ "$status" -eq 0 ]
}

@test "prepare_run_fixtures: does not create export_config.json when run export_config is null" {
  # Arrange — scenario has export_config: null
  local yaml_file
  yaml_file=$(write_null_config_scenario_yaml "null-config")
  local out_dir="$BATS_TEST_TMPDIR/run-null-out"
  mkdir -p "$out_dir"

  # Act — run has null export_config
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — file must NOT be present
  [ "$status" -eq 0 ]
  [ ! -f "$out_dir/export_config.json" ]
}

@test "prepare_run_fixtures: creates the scenario_dir when it does not exist" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/new-dir-$$"
  # Deliberately NOT creating out_dir

  # Act
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — function should create the directory and succeed
  [ "$status" -eq 0 ]
  [ -d "$out_dir" ]
}

@test "prepare_run_fixtures: removes stale agent_result.txt when run has no agent_result" {
  # Arrange — create a stale file in the output dir, then use a run with no agent_result
  local yaml_file="$SCENARIOS_DIR/no-agent-result.yaml"
  cat > "$yaml_file" <<YAML
name: no-agent-result
level: [integration]
run:
  export_config: null
YAML
  local out_dir="$BATS_TEST_TMPDIR/stale-out"
  mkdir -p "$out_dir"
  echo "stale content" > "$out_dir/agent_result.txt"

  # Act — no-agent-result run has no agent_result field at all
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — stale file should be gone
  [ "$status" -eq 0 ]
  [ ! -f "$out_dir/agent_result.txt" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# verify_run
# ═══════════════════════════════════════════════════════════════════════════════

@test "verify_run: calls assert_workflow_succeeded for the given workflow" {
  # Arrange — mock assert_workflow_succeeded to record calls.
  # Call directly (not via `run`) so the mock writes to the log in the same
  # process; `run` spawns a subshell where exports do not propagate back.
  local call_log="$WORK_DIR/assert-calls.txt"
  touch "$call_log"

  assert_workflow_succeeded() {
    echo "assert_workflow_succeeded called with: $*" >> "$call_log"
  }
  export -f assert_workflow_succeeded


  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act — direct call keeps mock side-effects visible in this shell.
  verify_run "$yaml_file" "pure-agent-test-wf"

  # Assert
  grep -q "assert_workflow_succeeded called with: pure-agent-test-wf" "$call_log"
}

@test "verify_run: fails when assert_workflow_succeeded fails" {
  # Arrange
  assert_workflow_succeeded() {
    return 1
  }
  export -f assert_workflow_succeeded


  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act
  run verify_run "$yaml_file" "failing-wf"

  # Assert
  [ "$status" -ne 0 ]
}

@test "verify_run: exits cleanly on success" {
  # Arrange
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act
  run verify_run "$yaml_file" "my-wf"

  # Assert — function must exit cleanly
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# verify_run — S3 transcript upload verification
# ═══════════════════════════════════════════════════════════════════════════════

@test "verify_run: calls S3 transcript assertion when S3_ENDPOINT_URL is set" {
  # Arrange
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_s3_transcript_exists() {
    echo "assert_s3_transcript_exists called" >> "$WORK_DIR/s3-calls.txt"
    return 0
  }
  export -f assert_s3_transcript_exists
  export S3_ENDPOINT_URL="http://localstack.pure-agent.svc.cluster.local:4566"

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  touch "$WORK_DIR/s3-calls.txt"

  # Act
  verify_run "$yaml_file" "test-wf"

  # Assert
  grep -q "assert_s3_transcript_exists called" "$WORK_DIR/s3-calls.txt"
}

@test "verify_run: skips S3 assertions when S3_ENDPOINT_URL is not set" {
  # Arrange
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_s3_transcript_exists() {
    echo "SHOULD NOT BE CALLED" >> "$WORK_DIR/s3-calls.txt"
    return 1
  }
  export -f assert_s3_transcript_exists
  unset S3_ENDPOINT_URL

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  touch "$WORK_DIR/s3-calls.txt"

  # Act
  run verify_run "$yaml_file" "test-wf"

  # Assert — should pass and NOT call S3 assertions
  [ "$status" -eq 0 ]
  ! grep -q "SHOULD NOT BE CALLED" "$WORK_DIR/s3-calls.txt"
}

@test "verify_run: fails when S3 transcript assertion fails" {
  # Arrange
  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_s3_transcript_exists() { return 1; }
  export -f assert_s3_transcript_exists
  export S3_ENDPOINT_URL="http://localstack:4566"

  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")

  # Act
  run verify_run "$yaml_file" "failing-s3-wf"

  # Assert
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# prepare_run_fixtures — transcript fixtures
# ═══════════════════════════════════════════════════════════════════════════════

@test "prepare_run_fixtures: creates transcript fixture when session_id is present" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/transcript-out"
  mkdir -p "$out_dir"

  # Act
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — transcript should be created using session_id from export_config
  [ "$status" -eq 0 ]
  [ -d "$out_dir/transcripts" ]
  [ -f "$out_dir/transcripts/mock-session-0.jsonl" ]
}

@test "prepare_run_fixtures: transcript fixture contains valid JSONL" {
  # Arrange
  local yaml_file
  yaml_file=$(write_scenario_yaml "none-action")
  local out_dir="$BATS_TEST_TMPDIR/transcript-jsonl-out"
  mkdir -p "$out_dir"

  # Act
  prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — each line should be valid JSON
  while IFS= read -r line; do
    echo "$line" | jq . > /dev/null 2>&1
    [ $? -eq 0 ]
  done < "$out_dir/transcripts/mock-session-0.jsonl"
}

@test "prepare_run_fixtures: no transcript when export_config is null" {
  # Arrange
  local yaml_file
  yaml_file=$(write_null_config_scenario_yaml "null-config")
  local out_dir="$BATS_TEST_TMPDIR/no-transcript-out"
  mkdir -p "$out_dir"

  # Act
  run prepare_run_fixtures "$yaml_file" "$out_dir"

  # Assert — no transcript directory should be created
  [ "$status" -eq 0 ]
  [ ! -d "$out_dir/transcripts" ]
}
