#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for Level ② functions in e2e/run-argo.sh
#
# TDD Red Phase: All level-2 functions currently return early with a [SKIP] message.
# These tests define the expected behaviour once the skip lines are removed.
#
# All tests run without a real Kubernetes cluster or Argo installation.
# External commands (kubectl, argo, yq, curl) are replaced by bash function stubs.

source "$BATS_TEST_DIRNAME/test-helper.sh"

RUN_ARGO_SCRIPT="$BATS_TEST_DIRNAME/../../run-argo.sh"
SCENARIOS_DIR="$BATS_TEST_DIRNAME/../../scenarios"

setup() {
  common_setup

  # Shared env for all Level ② tests
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-level2"
  export MOCK_AGENT_IMAGE="ghcr.io/dlddu/pure-agent/mock-agent:latest"
  export MOCK_API_URL="http://localhost:4000"
  export WORKFLOW_TIMEOUT="600"
  export LEVEL="2"
  export SCENARIOS_DIR

  # Source run-argo.sh in --source-only mode so we can unit-test individual functions.
  # shellcheck disable=SC1090
  source "$RUN_ARGO_SCRIPT" --source-only
}

# ─────────────────────────────────────────────────────────────────────────────
# check_prerequisites (Level 2 branch)
# ─────────────────────────────────────────────────────────────────────────────

@test "check_prerequisites (level 2): passes when argo, kubectl, jq, yq are all present" {
  # Arrange — stub all required commands to succeed
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  export LEVEL="2"

  run check_prerequisites

  [ "$status" -eq 0 ]
}

@test "check_prerequisites (level 2): fails when argo is not installed" {
  # Arrange — make `command -v argo` fail by hiding it
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  export LEVEL="2"

  # Override `command` to simulate missing argo
  command() {
    if [[ "$2" == "argo" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (level 2): fails when kubectl is not installed" {
  export LEVEL="2"

  command() {
    if [[ "$2" == "kubectl" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (level 2): fails when jq is not installed" {
  export LEVEL="2"

  command() {
    if [[ "$2" == "jq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (level 2): fails when yq is not installed" {
  export LEVEL="2"

  command() {
    if [[ "$2" == "yq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run check_prerequisites

  [ "$status" -ne 0 ]
}

@test "check_prerequisites (level 2): does NOT require LINEAR_API_KEY" {
  # Level 2 should not check real API credentials
  unset LINEAR_API_KEY
  export LEVEL="2"

  command() { builtin command "$@"; }
  export -f command

  # Stub all required binaries as present
  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  run check_prerequisites

  [ "$status" -eq 0 ]
}

@test "check_prerequisites (level 2): does NOT require GITHUB_TOKEN" {
  unset GITHUB_TOKEN
  export LEVEL="2"

  command() { builtin command "$@"; }
  export -f command

  argo()    { return 0; }
  kubectl() { return 0; }
  jq()      { return 0; }
  yq()      { return 0; }
  export -f argo kubectl jq yq

  run check_prerequisites

  [ "$status" -eq 0 ]
}

@test "check_prerequisites (level 2): failure output mentions the missing command" {
  export LEVEL="2"

  command() {
    if [[ "$2" == "yq" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run check_prerequisites

  [ "$status" -ne 0 ]
  [[ "$output" == *"yq"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# _level2_place_cycle_fixtures
# ─────────────────────────────────────────────────────────────────────────────

@test "_level2_place_cycle_fixtures: creates export_config.json for cycle 0 of continue-then-stop" {
  # Arrange
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-output"
  mkdir -p "$scenario_dir"
  local yaml_file="$SCENARIOS_DIR/continue-then-stop.yaml"

  # Stub yq to produce realistic output for the continue-then-stop scenario
  yq() {
    local path="$2"
    case "$path" in
      ".cycles[0].export_config")
        echo '{"linear_issue_id":"mock-issue-id","actions":["continue"]}'
        ;;
      "-o=json .cycles[0].export_config")
        echo '{"linear_issue_id":"mock-issue-id","actions":["continue"]}'
        ;;
      ".cycles[0].agent_result // \"\"")
        echo "Cycle 0 done, continuing..."
        ;;
    esac
  }
  export -f yq

  # Act
  run _level2_place_cycle_fixtures "$yaml_file" "0" "$scenario_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$scenario_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: export_config.json content is valid JSON" {
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-ec-json"
  mkdir -p "$scenario_dir"

  yq() {
    case "${*}" in
      *".cycles[0].export_config"*)
        echo '{"linear_issue_id":"mock-issue-id","actions":["continue"],"session_id":"mock-session-cycle0"}'
        ;;
      *".cycles[0].agent_result"*)
        echo "Cycle 0 done"
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures "$SCENARIOS_DIR/continue-then-stop.yaml" "0" "$scenario_dir"

  # Validate that the resulting file is parseable JSON
  run jq . "$scenario_dir/export_config.json"
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: creates agent_result.txt when agent_result is non-empty" {
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-agent"
  mkdir -p "$scenario_dir"

  yq() {
    case "${*}" in
      *".cycles[0].export_config"*)
        echo '{"actions":["continue"]}'
        ;;
      *".cycles[0].agent_result"*)
        echo "Cycle 0 done, continuing..."
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures "$SCENARIOS_DIR/continue-then-stop.yaml" "0" "$scenario_dir"

  [ -f "$scenario_dir/agent_result.txt" ]
}

@test "_level2_place_cycle_fixtures: agent_result.txt preserves the text content" {
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-agent-content"
  mkdir -p "$scenario_dir"
  local expected_result="Cycle 0 done, continuing..."

  yq() {
    case "${*}" in
      *".cycles[0].export_config"*)
        echo '{"actions":["continue"]}'
        ;;
      *".cycles[0].agent_result"*)
        echo "$expected_result"
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures "$SCENARIOS_DIR/continue-then-stop.yaml" "0" "$scenario_dir"

  local actual
  actual=$(cat "$scenario_dir/agent_result.txt")
  [ "$actual" = "$expected_result" ]
}

@test "_level2_place_cycle_fixtures: does NOT create export_config.json when export_config is null" {
  # depth-limit scenario: cycle 0 export_config is null
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-null-ec"
  mkdir -p "$scenario_dir"

  yq() {
    case "${*}" in
      *".cycles[0].export_config"*)
        echo "null"
        ;;
      *".cycles[0].agent_result"*)
        echo "Depth limit reached"
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures "$SCENARIOS_DIR/depth-limit.yaml" "0" "$scenario_dir"

  [ ! -f "$scenario_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: creates the scenario_dir if it does not exist" {
  local scenario_dir="$BATS_TEST_TMPDIR/new-nonexistent-dir"

  yq() {
    case "${*}" in
      *"export_config"*)
        echo "null"
        ;;
      *"agent_result"*)
        echo ""
        ;;
    esac
  }
  export -f yq

  run _level2_place_cycle_fixtures "$SCENARIOS_DIR/depth-limit.yaml" "0" "$scenario_dir"

  [ "$status" -eq 0 ]
  [ -d "$scenario_dir" ]
}

@test "_level2_place_cycle_fixtures: places cycle 1 fixtures correctly for continue-then-stop" {
  local scenario_dir="$BATS_TEST_TMPDIR/fixtures-cycle1"
  mkdir -p "$scenario_dir"

  yq() {
    case "${*}" in
      *".cycles[1].export_config"*)
        echo '{"actions":["none"]}'
        ;;
      *".cycles[1].agent_result"*)
        echo "Cycle 1 done, stopping."
        ;;
    esac
  }
  export -f yq

  run _level2_place_cycle_fixtures "$SCENARIOS_DIR/continue-then-stop.yaml" "1" "$scenario_dir"

  [ "$status" -eq 0 ]
  [ -f "$scenario_dir/export_config.json" ]
  [ -f "$scenario_dir/agent_result.txt" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# _level2_submit_mock_workflow
# ─────────────────────────────────────────────────────────────────────────────

@test "_level2_submit_mock_workflow: calls kubectl to create a ConfigMap" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-dir"
  mkdir -p "$scenario_dir"
  echo '{"actions":["continue"]}' > "$scenario_dir/export_config.json"

  local kubectl_calls_file="$WORK_DIR/kubectl-calls.txt"
  touch "$kubectl_calls_file"

  kubectl() {
    echo "kubectl $*" >> "$kubectl_calls_file"
    # For apply -f - pass-through: just succeed
    return 0
  }
  export -f kubectl
  export kubectl_calls_file

  argo() {
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-mock-abc"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo

  run _level2_submit_mock_workflow "continue-then-stop" "0" "5" "$scenario_dir"

  [ "$status" -eq 0 ]
  grep -q "configmap\|ConfigMap\|create" "$kubectl_calls_file"
}

@test "_level2_submit_mock_workflow: calls argo submit with correct parameters" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-argo-dir"
  mkdir -p "$scenario_dir"
  echo '{"actions":["none"]}' > "$scenario_dir/export_config.json"

  local argo_args_file="$WORK_DIR/argo-args.txt"
  touch "$argo_args_file"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    echo "argo $*" >> "$argo_args_file"
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-mock-def"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo
  export argo_args_file

  run _level2_submit_mock_workflow "none-action" "0" "5" "$scenario_dir"

  [ "$status" -eq 0 ]
  grep -q "submit" "$argo_args_file"
}

@test "_level2_submit_mock_workflow: passes max_depth parameter to argo submit" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-depth-dir"
  mkdir -p "$scenario_dir"
  echo '{}' > "$scenario_dir/export_config.json"

  local argo_args_file="$WORK_DIR/argo-depth-args.txt"
  touch "$argo_args_file"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    echo "argo $*" >> "$argo_args_file"
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-mock-ghi"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo
  export argo_args_file

  run _level2_submit_mock_workflow "depth-limit" "0" "2" "$scenario_dir"

  [ "$status" -eq 0 ]
  grep -q "max_depth" "$argo_args_file"
  grep -q "2" "$argo_args_file"
}

@test "_level2_submit_mock_workflow: passes MOCK_AGENT_IMAGE to argo submit" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-image-dir"
  mkdir -p "$scenario_dir"
  echo '{}' > "$scenario_dir/export_config.json"

  local argo_args_file="$WORK_DIR/argo-image-args.txt"
  touch "$argo_args_file"

  export MOCK_AGENT_IMAGE="ghcr.io/dlddu/pure-agent/mock-agent:test"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    echo "argo $*" >> "$argo_args_file"
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-mock-jkl"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo
  export argo_args_file

  run _level2_submit_mock_workflow "none-action" "0" "5" "$scenario_dir"

  [ "$status" -eq 0 ]
  grep -q "mock-agent" "$argo_args_file"
}

@test "_level2_submit_mock_workflow: outputs the submitted workflow name" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-name-dir"
  mkdir -p "$scenario_dir"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-expected-name"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo

  run _level2_submit_mock_workflow "none-action" "0" "5" "$scenario_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"pure-agent-expected-name"* ]]
}

@test "_level2_submit_mock_workflow: fails when argo submit command fails" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-fail-dir"
  mkdir -p "$scenario_dir"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    case "$*" in
      *submit*)
        return 1
        ;;
    esac
  }
  export -f argo

  run _level2_submit_mock_workflow "none-action" "0" "5" "$scenario_dir"

  [ "$status" -ne 0 ]
}

@test "_level2_submit_mock_workflow: fails when argo wait returns non-zero" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-wait-fail-dir"
  mkdir -p "$scenario_dir"

  kubectl() { return 0; }
  export -f kubectl

  argo() {
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-wait-fail"}}'
        ;;
      *wait*)
        return 1
        ;;
      *get*)
        echo '{"status":{"phase":"Failed"}}'
        ;;
    esac
  }
  export -f argo

  run _level2_submit_mock_workflow "none-action" "0" "5" "$scenario_dir"

  [ "$status" -ne 0 ]
}

@test "_level2_submit_mock_workflow: creates empty ConfigMap when no fixture files exist" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-empty-cm-dir"
  mkdir -p "$scenario_dir"
  # No export_config.json or agent_result.txt — empty ConfigMap expected

  local kubectl_calls_file="$WORK_DIR/kubectl-empty-calls.txt"
  touch "$kubectl_calls_file"

  kubectl() {
    echo "kubectl $*" >> "$kubectl_calls_file"
    return 0
  }
  export -f kubectl
  export kubectl_calls_file

  argo() {
    case "$*" in
      *submit*)
        echo '{"metadata":{"name":"pure-agent-empty-cm"}}'
        ;;
      *wait*)
        return 0
        ;;
    esac
  }
  export -f argo

  run _level2_submit_mock_workflow "depth-limit" "0" "2" "$scenario_dir"

  [ "$status" -eq 0 ]
  grep -q "configmap\|ConfigMap\|create" "$kubectl_calls_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# _level2_verify_cycle
# ─────────────────────────────────────────────────────────────────────────────

@test "_level2_verify_cycle: passes when workflow Succeeded and no assertions defined" {
  # Arrange — minimal scenario with no assertions beyond workflow phase
  local yaml_file="$FIXTURE_DIR/minimal.yaml"
  cat > "$yaml_file" <<'YAML'
name: minimal
level: [2]
cycles:
  - export_config: null
    agent_result: "done"
assertions: {}
YAML

  kubectl() {
    # Return Succeeded for workflow phase check
    echo "Succeeded"
  }
  export -f kubectl

  yq() {
    case "${*}" in
      *"router_decisions"*)
        echo ""
        ;;
      *"router_decision"*)
        echo ""
        ;;
      *"linear_comment"*)
        echo ""
        ;;
      *"github_pr"*)
        echo "false"
        ;;
    esac
  }
  export -f yq

  run _level2_verify_cycle "$yaml_file" "pure-agent-abcde" "0"

  [ "$status" -eq 0 ]
}

@test "_level2_verify_cycle: calls assert_workflow_succeeded with the workflow name" {
  local yaml_file="$FIXTURE_DIR/verify-wf.yaml"
  cat > "$yaml_file" <<'YAML'
name: verify-wf
level: [2]
cycles:
  - export_config: null
    agent_result: "done"
assertions: {}
YAML

  local assert_calls_file="$WORK_DIR/assert-calls.txt"
  touch "$assert_calls_file"

  # Stub assert_workflow_succeeded to record its argument
  assert_workflow_succeeded() {
    echo "assert_workflow_succeeded called with: $1" >> "$assert_calls_file"
    return 0
  }
  export -f assert_workflow_succeeded

  yq() {
    echo ""
  }
  export -f yq

  _level2_verify_cycle "$yaml_file" "pure-agent-verify-test" "0"

  grep -q "pure-agent-verify-test" "$assert_calls_file"
}

@test "_level2_verify_cycle: fails when assert_workflow_succeeded fails" {
  local yaml_file="$FIXTURE_DIR/verify-fail.yaml"
  cat > "$yaml_file" <<'YAML'
name: verify-fail
level: [2]
cycles:
  - export_config: null
    agent_result: "done"
assertions: {}
YAML

  assert_workflow_succeeded() {
    return 1
  }
  export -f assert_workflow_succeeded

  yq() { echo ""; }
  export -f yq

  run _level2_verify_cycle "$yaml_file" "pure-agent-abcde" "0"

  [ "$status" -ne 0 ]
}

@test "_level2_verify_cycle: calls assert_mock_api when router_decision assertion is defined" {
  local yaml_file="$FIXTURE_DIR/verify-router.yaml"
  cat > "$yaml_file" <<'YAML'
name: verify-router
level: [2]
cycles:
  - export_config: null
    agent_result: "done"
assertions:
  router_decision: "stop"
YAML

  local mock_api_calls_file="$WORK_DIR/mock-api-calls.txt"
  touch "$mock_api_calls_file"

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_mock_api() {
    echo "assert_mock_api $1 $2" >> "$mock_api_calls_file"
    return 0
  }
  export -f assert_mock_api

  yq() {
    case "${*}" in
      *"router_decisions[0]"*)
        echo ""
        ;;
      *"router_decision //"*)
        echo "stop"
        ;;
      *"linear_comment"*)
        echo ""
        ;;
      *"github_pr"*)
        echo "false"
        ;;
    esac
  }
  export -f yq

  _level2_verify_cycle "$yaml_file" "pure-agent-abcde" "0"

  grep -q "stop" "$mock_api_calls_file"
}

@test "_level2_verify_cycle: calls assert_mock_api for linear_comment body_contains assertion" {
  local yaml_file="$FIXTURE_DIR/verify-comment.yaml"
  cat > "$yaml_file" <<'YAML'
name: verify-comment
level: [2]
cycles:
  - export_config: null
    agent_result: "done"
assertions:
  linear_comment:
    body_contains: "작업 완료"
YAML

  local mock_api_calls_file="$WORK_DIR/mock-api-comment-calls.txt"
  touch "$mock_api_calls_file"

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_mock_api() {
    echo "assert_mock_api $1 $2" >> "$mock_api_calls_file"
    return 0
  }
  export -f assert_mock_api

  yq() {
    case "${*}" in
      *"router_decisions"*)
        echo ""
        ;;
      *"router_decision"*)
        echo ""
        ;;
      *"body_contains"*)
        echo "작업 완료"
        ;;
      *"github_pr"*)
        echo "false"
        ;;
    esac
  }
  export -f yq

  _level2_verify_cycle "$yaml_file" "pure-agent-abcde" "0"

  grep -q "작업 완료" "$mock_api_calls_file"
}

@test "_level2_verify_cycle: does NOT call assert_mock_api when assertions are empty" {
  local yaml_file="$FIXTURE_DIR/verify-empty.yaml"
  cat > "$yaml_file" <<'YAML'
name: verify-empty
level: [2]
cycles:
  - export_config: null
assertions: {}
YAML

  local mock_api_calls_file="$WORK_DIR/mock-api-empty-calls.txt"
  touch "$mock_api_calls_file"

  assert_workflow_succeeded() { return 0; }
  export -f assert_workflow_succeeded

  assert_mock_api() {
    echo "assert_mock_api called" >> "$mock_api_calls_file"
    return 0
  }
  export -f assert_mock_api

  yq() { echo ""; }
  export -f yq

  _level2_verify_cycle "$yaml_file" "pure-agent-abcde" "0"

  local call_count
  call_count=$(wc -l < "$mock_api_calls_file")
  [ "$call_count" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# run_scenario_level2
# ─────────────────────────────────────────────────────────────────────────────

@test "run_scenario_level2: passes for none-action scenario with one cycle" {
  # Arrange — stub all external calls

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "1"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "none-action"
        ;;
      *"export_config"*)
        echo '{"actions":["none"]}'
        ;;
      *"agent_result"*)
        echo "No action needed."
        ;;
      *"router_decisions"*)
        echo ""
        ;;
      *"router_decision"*)
        echo "stop"
        ;;
      *"body_contains"*)
        echo ""
        ;;
      *"github_pr"*)
        echo "false"
        ;;
    esac
  }
  export -f yq

  kubectl() { return 0; }
  export -f kubectl

  curl() {
    case "$*" in
      *"/assertions/reset"*)
        return 0
        ;;
    esac
    return 0
  }
  export -f curl

  argo() {
    case "$*" in
      *"submit"*)
        echo '{"metadata":{"name":"pure-agent-none-action-1"}}'
        ;;
      *"wait"*)
        return 0
        ;;
    esac
  }
  export -f argo

  assert_workflow_succeeded()  { return 0; }
  assert_daemon_pods_ready()   { return 0; }
  assert_work_dir_clean()      { return 0; }
  assert_mock_api()            { return 0; }
  export -f assert_workflow_succeeded assert_daemon_pods_ready
  export -f assert_work_dir_clean assert_mock_api

  run run_scenario_level2 "none-action"

  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: fails when scenario YAML file does not exist" {
  run run_scenario_level2 "nonexistent-scenario-xyz"

  [ "$status" -ne 0 ]
}

@test "run_scenario_level2: skips gracefully when cycles array is empty" {
  # Arrange — create a temp scenario file with no cycles
  local yaml_file="$FIXTURE_DIR/no-cycles.yaml"
  cat > "$yaml_file" <<'YAML'
name: no-cycles
level: [2]
cycles: []
assertions: {}
YAML

  # Temporarily override SCENARIOS_DIR to our fixture directory
  local orig_scenarios_dir="$SCENARIOS_DIR"
  export SCENARIOS_DIR="$FIXTURE_DIR"

  # Create the file with exactly the expected name
  cp "$yaml_file" "$FIXTURE_DIR/no-cycles.yaml"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "0"
        ;;
    esac
  }
  export -f yq

  run run_scenario_level2 "no-cycles"

  export SCENARIOS_DIR="$orig_scenarios_dir"

  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: calls _level2_place_cycle_fixtures for each cycle" {
  local place_calls_file="$WORK_DIR/place-calls.txt"
  touch "$place_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "2"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "continue-then-stop"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() {
    echo "_level2_place_cycle_fixtures called: cycle=$2" >> "$place_calls_file"
    return 0
  }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "pure-agent-orchestration-$2"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() { return 0; }
  export -f _level2_verify_cycle

  assert_run_cycle_count()   { return 0; }
  assert_max_depth_termination() { return 0; }
  assert_daemon_pods_ready() { return 0; }
  assert_work_dir_clean()    { return 0; }
  export -f assert_run_cycle_count assert_max_depth_termination
  export -f assert_daemon_pods_ready assert_work_dir_clean

  curl() { return 0; }
  export -f curl

  export place_calls_file

  run run_scenario_level2 "continue-then-stop"

  [ "$status" -eq 0 ]
  local call_count
  call_count=$(wc -l < "$place_calls_file")
  [ "$call_count" -eq 2 ]
}

@test "run_scenario_level2: calls _level2_submit_mock_workflow for each cycle" {
  local submit_calls_file="$WORK_DIR/submit-orch-calls.txt"
  touch "$submit_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "2"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "continue-then-stop"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "_level2_submit_mock_workflow called: cycle=$2" >> "$submit_calls_file"
    echo "pure-agent-submit-$2"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() { return 0; }
  export -f _level2_verify_cycle

  assert_run_cycle_count()       { return 0; }
  assert_max_depth_termination() { return 0; }
  assert_daemon_pods_ready()     { return 0; }
  assert_work_dir_clean()        { return 0; }
  export -f assert_run_cycle_count assert_max_depth_termination
  export -f assert_daemon_pods_ready assert_work_dir_clean

  curl() { return 0; }
  export -f curl

  export submit_calls_file

  run run_scenario_level2 "continue-then-stop"

  [ "$status" -eq 0 ]
  local call_count
  call_count=$(wc -l < "$submit_calls_file")
  [ "$call_count" -eq 2 ]
}

@test "run_scenario_level2: calls assert_run_cycle_count for continue-then-stop scenario" {
  local run_cycle_calls_file="$WORK_DIR/run-cycle-calls.txt"
  touch "$run_cycle_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "2"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "continue-then-stop"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "pure-agent-cts-$2"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() { return 0; }
  export -f _level2_verify_cycle

  assert_run_cycle_count() {
    echo "assert_run_cycle_count called: wf=$1 count=$2" >> "$run_cycle_calls_file"
    return 0
  }
  export -f assert_run_cycle_count

  assert_max_depth_termination() { return 0; }
  assert_daemon_pods_ready()     { return 0; }
  assert_work_dir_clean()        { return 0; }
  export -f assert_max_depth_termination assert_daemon_pods_ready assert_work_dir_clean

  curl() { return 0; }
  export -f curl

  export run_cycle_calls_file

  run run_scenario_level2 "continue-then-stop"

  [ "$status" -eq 0 ]
  local call_count
  call_count=$(wc -l < "$run_cycle_calls_file")
  [ "$call_count" -ge 1 ]
}

@test "run_scenario_level2: calls assert_max_depth_termination for depth-limit scenario" {
  local depth_calls_file="$WORK_DIR/depth-calls.txt"
  touch "$depth_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "1"
        ;;
      *"max_depth"*)
        echo "2"
        ;;
      *"name"*)
        echo "depth-limit"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "pure-agent-depth-0"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() { return 0; }
  export -f _level2_verify_cycle

  assert_run_cycle_count() { return 0; }
  assert_max_depth_termination() {
    echo "assert_max_depth_termination called: wf=$1 depth=$2" >> "$depth_calls_file"
    return 0
  }
  assert_daemon_pods_ready() { return 0; }
  assert_work_dir_clean()    { return 0; }
  export -f assert_run_cycle_count assert_max_depth_termination
  export -f assert_daemon_pods_ready assert_work_dir_clean

  curl() { return 0; }
  export -f curl

  export depth_calls_file

  run run_scenario_level2 "depth-limit"

  [ "$status" -eq 0 ]
  local call_count
  call_count=$(wc -l < "$depth_calls_file")
  [ "$call_count" -ge 1 ]
}

@test "run_scenario_level2: calls assert_work_dir_clean for each workflow" {
  local work_dir_calls_file="$WORK_DIR/work-dir-calls.txt"
  touch "$work_dir_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "1"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "none-action"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "pure-agent-work-dir-0"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() { return 0; }
  export -f _level2_verify_cycle

  assert_run_cycle_count()       { return 0; }
  assert_max_depth_termination() { return 0; }
  assert_daemon_pods_ready()     { return 0; }
  assert_work_dir_clean() {
    echo "assert_work_dir_clean called: wf=$1" >> "$work_dir_calls_file"
    return 0
  }
  export -f assert_run_cycle_count assert_max_depth_termination
  export -f assert_daemon_pods_ready assert_work_dir_clean

  curl() { return 0; }
  export -f curl

  export work_dir_calls_file

  run run_scenario_level2 "none-action"

  [ "$status" -eq 0 ]
  local call_count
  call_count=$(wc -l < "$work_dir_calls_file")
  [ "$call_count" -ge 1 ]
}

@test "run_scenario_level2: fails when _level2_verify_cycle fails" {
  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "1"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "none-action"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  export -f _level2_place_cycle_fixtures

  _level2_submit_mock_workflow() {
    echo "pure-agent-verify-fail-wf"
    return 0
  }
  export -f _level2_submit_mock_workflow

  _level2_verify_cycle() {
    return 1
  }
  export -f _level2_verify_cycle

  curl() { return 0; }
  export -f curl

  run run_scenario_level2 "none-action"

  [ "$status" -ne 0 ]
}

@test "run_scenario_level2: resets mock-api assertions before running" {
  local curl_calls_file="$WORK_DIR/curl-reset-calls.txt"
  touch "$curl_calls_file"

  yq() {
    case "${*}" in
      *"cycles | length"*)
        echo "1"
        ;;
      *"max_depth"*)
        echo "5"
        ;;
      *"name"*)
        echo "none-action"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f yq

  _level2_place_cycle_fixtures() { return 0; }
  _level2_submit_mock_workflow()  { echo "pure-agent-reset-wf"; return 0; }
  _level2_verify_cycle()          { return 0; }
  export -f _level2_place_cycle_fixtures _level2_submit_mock_workflow _level2_verify_cycle

  assert_run_cycle_count()       { return 0; }
  assert_max_depth_termination() { return 0; }
  assert_daemon_pods_ready()     { return 0; }
  assert_work_dir_clean()        { return 0; }
  export -f assert_run_cycle_count assert_max_depth_termination
  export -f assert_daemon_pods_ready assert_work_dir_clean

  curl() {
    echo "curl $*" >> "$curl_calls_file"
    return 0
  }
  export -f curl
  export curl_calls_file

  run run_scenario_level2 "none-action"

  [ "$status" -eq 0 ]
  grep -q "assertions/reset" "$curl_calls_file"
}
