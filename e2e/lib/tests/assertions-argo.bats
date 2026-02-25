#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/assertions-argo.sh
#
# TDD Red Phase: Each function currently has a skip guard.
# These tests define the exact behaviour expected once the skip lines are removed.
#
# All tests run without a real Kubernetes cluster — kubectl, argo, jq, and curl
# are replaced by bash function stubs exported into the test environment.

source "$BATS_TEST_DIRNAME/test-helper.sh"

LIB_DIR_ARGO="$BATS_TEST_DIRNAME/.."

setup() {
  common_setup
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-level2"
  export MOCK_API_URL="http://localhost:4000"
  # Source the library in --source-only mode so function bodies are loaded
  # but no top-level side effects run.
  # shellcheck disable=SC1090
  source "$LIB_DIR_ARGO/assertions-argo.sh" --source-only
}

# ─────────────────────────────────────────────────────────────────────────────
# assert_workflow_succeeded
# ─────────────────────────────────────────────────────────────────────────────

@test "assert_workflow_succeeded: passes when workflow phase is Succeeded" {
  # Arrange — stub kubectl to report Succeeded
  kubectl() {
    # Any call to `kubectl get workflow` prints the phase
    echo "Succeeded"
  }
  export -f kubectl

  # Act
  run assert_workflow_succeeded "pure-agent-abcde"

  # Assert
  [ "$status" -eq 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Failed" {
  kubectl() {
    echo "Failed"
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Running" {
  kubectl() {
    echo "Running"
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Error" {
  kubectl() {
    echo "Error"
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: failure output mentions the workflow name" {
  kubectl() {
    echo "Failed"
  }
  export -f kubectl

  run assert_workflow_succeeded "my-specific-workflow"

  [ "$status" -ne 0 ]
  [[ "$output" == *"my-specific-workflow"* ]]
}

@test "assert_workflow_succeeded: failure output mentions expected phase Succeeded" {
  kubectl() {
    echo "Error"
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-xyz"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Succeeded"* ]]
}

@test "assert_workflow_succeeded: fails when kubectl command itself fails" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: uses provided namespace argument" {
  # Arrange — capture arguments to verify namespace is forwarded
  local captured_args_file="$WORK_DIR/kubectl-args.txt"

  kubectl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo "Succeeded"
  }
  export -f kubectl
  export captured_args_file

  run assert_workflow_succeeded "pure-agent-abcde" "custom-ns"

  [ "$status" -eq 0 ]
  grep -q "custom-ns" "$captured_args_file"
}

@test "assert_workflow_succeeded: defaults to NAMESPACE env var when no namespace argument" {
  local captured_args_file="$WORK_DIR/kubectl-args.txt"
  export NAMESPACE="default-ns"

  kubectl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo "Succeeded"
  }
  export -f kubectl
  export captured_args_file

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -eq 0 ]
  grep -q "default-ns" "$captured_args_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# assert_daemon_pods_ready
# ─────────────────────────────────────────────────────────────────────────────

@test "assert_daemon_pods_ready: passes when kubectl wait succeeds" {
  kubectl() {
    # Simulate `kubectl wait pod --for=condition=Ready` succeeding
    return 0
  }
  export -f kubectl

  run assert_daemon_pods_ready "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_daemon_pods_ready: passes when primary wait fails but fallback wait succeeds" {
  # The function falls back to a broader label selector on first failure.
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"
    if [[ "$n" -eq 1 ]]; then
      # First call (mcp-server label filter) fails
      return 1
    fi
    # Second call (workflow-only label) succeeds
    return 0
  }
  export -f kubectl
  export call_count_file

  run assert_daemon_pods_ready "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_daemon_pods_ready: fails when both kubectl wait calls fail" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_daemon_pods_ready "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_daemon_pods_ready: failure output mentions the workflow name" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_daemon_pods_ready "my-workflow-xyz"

  [ "$status" -ne 0 ]
  [[ "$output" == *"my-workflow-xyz"* ]]
}

@test "assert_daemon_pods_ready: uses provided namespace argument" {
  local captured_args_file="$WORK_DIR/kubectl-args.txt"

  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    return 0
  }
  export -f kubectl
  export captured_args_file

  run assert_daemon_pods_ready "pure-agent-abcde" "custom-ns"

  [ "$status" -eq 0 ]
  grep -q "custom-ns" "$captured_args_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# assert_run_cycle_count
# ─────────────────────────────────────────────────────────────────────────────

@test "assert_run_cycle_count: passes when actual count equals expected count" {
  # Arrange — kubectl+jq pipeline returns 2 run-cycle nodes
  kubectl() {
    # Output JSON that jq will process; the function pipes through jq internally.
    # We return a JSON blob with two run-cycle Pod nodes.
    cat <<'JSON'
{
  "status": {
    "nodes": {
      "node-1": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"},
      "node-2": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"},
      "node-3": {"templateName": "other-step", "type": "Pod", "phase": "Succeeded"}
    }
  }
}
JSON
  }
  export -f kubectl

  run assert_run_cycle_count "pure-agent-abcde" "2"

  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: fails when actual count is less than expected" {
  kubectl() {
    cat <<'JSON'
{
  "status": {
    "nodes": {
      "node-1": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"}
    }
  }
}
JSON
  }
  export -f kubectl

  # Expect 2 but only 1 exists
  run assert_run_cycle_count "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
}

@test "assert_run_cycle_count: fails when actual count is more than expected" {
  kubectl() {
    cat <<'JSON'
{
  "status": {
    "nodes": {
      "node-1": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"},
      "node-2": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"},
      "node-3": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"}
    }
  }
}
JSON
  }
  export -f kubectl

  # Expect 2 but 3 exist
  run assert_run_cycle_count "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
}

@test "assert_run_cycle_count: passes when expected is 1 and exactly 1 run-cycle node exists" {
  kubectl() {
    cat <<'JSON'
{
  "status": {
    "nodes": {
      "node-1": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"}
    }
  }
}
JSON
  }
  export -f kubectl

  run assert_run_cycle_count "pure-agent-abcde" "1"

  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: only counts nodes with type Pod (not DAG nodes)" {
  kubectl() {
    cat <<'JSON'
{
  "status": {
    "nodes": {
      "dag-node": {"templateName": "run-cycle", "type": "DAG", "phase": "Succeeded"},
      "pod-node": {"templateName": "run-cycle", "type": "Pod", "phase": "Succeeded"}
    }
  }
}
JSON
  }
  export -f kubectl

  # Only 1 Pod-type run-cycle node
  run assert_run_cycle_count "pure-agent-abcde" "1"

  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: failure output mentions expected and actual counts" {
  kubectl() {
    cat <<'JSON'
{"status": {"nodes": {}}}
JSON
  }
  export -f kubectl

  # Expect 2, get 0
  run assert_run_cycle_count "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
  [[ "$output" == *"2"* ]]
}

@test "assert_run_cycle_count: fails when kubectl command fails" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_run_cycle_count "pure-agent-abcde" "1"

  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# assert_max_depth_termination
# ─────────────────────────────────────────────────────────────────────────────

@test "assert_max_depth_termination: passes when workflow Succeeded and cycle_count equals max_depth" {
  # The function reads phase via jsonpath then counts run-cycle nodes.
  # We need kubectl to handle both call shapes.
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"

    if [[ "$n" -eq 1 ]]; then
      # First call: jsonpath for .status.phase
      echo "Succeeded"
    else
      # Second call: -o json for jq processing
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "node-1": {"templateName": "run-cycle", "type": "Pod"},
      "node-2": {"templateName": "run-cycle", "type": "Pod"}
    }
  }
}
JSON
    fi
  }
  export -f kubectl
  export call_count_file

  # max_depth=2, cycle_count=2 — should pass
  run assert_max_depth_termination "pure-agent-abcde" "2"

  [ "$status" -eq 0 ]
}

@test "assert_max_depth_termination: passes when cycle_count is less than max_depth" {
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"

    if [[ "$n" -eq 1 ]]; then
      echo "Succeeded"
    else
      cat <<'JSON'
{"status":{"nodes":{"node-1":{"templateName":"run-cycle","type":"Pod"}}}}
JSON
    fi
  }
  export -f kubectl
  export call_count_file

  # cycle_count=1, max_depth=2 — still within limit
  run assert_max_depth_termination "pure-agent-abcde" "2"

  [ "$status" -eq 0 ]
}

@test "assert_max_depth_termination: fails when workflow phase is not Succeeded" {
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"

    if [[ "$n" -eq 1 ]]; then
      echo "Failed"
    else
      echo '{"status":{"nodes":{}}}'
    fi
  }
  export -f kubectl
  export call_count_file

  run assert_max_depth_termination "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
}

@test "assert_max_depth_termination: fails when cycle_count exceeds max_depth" {
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"

    if [[ "$n" -eq 1 ]]; then
      echo "Succeeded"
    else
      # 3 run-cycle nodes but max_depth=2
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "n1": {"templateName":"run-cycle","type":"Pod"},
      "n2": {"templateName":"run-cycle","type":"Pod"},
      "n3": {"templateName":"run-cycle","type":"Pod"}
    }
  }
}
JSON
    fi
  }
  export -f kubectl
  export call_count_file

  run assert_max_depth_termination "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
}

@test "assert_max_depth_termination: failure output mentions max_depth value" {
  local call_count_file="$WORK_DIR/call-count.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"

    if [[ "$n" -eq 1 ]]; then
      echo "Failed"
    else
      echo '{"status":{"nodes":{}}}'
    fi
  }
  export -f kubectl
  export call_count_file

  run assert_max_depth_termination "pure-agent-abcde" "3"

  [ "$status" -ne 0 ]
  [[ "$output" == *"3"* ]]
}

@test "assert_max_depth_termination: fails when kubectl command fails on first call" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_max_depth_termination "pure-agent-abcde" "2"

  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# assert_work_dir_clean
# ─────────────────────────────────────────────────────────────────────────────

@test "assert_work_dir_clean: passes when cleanup node phase is Succeeded" {
  kubectl() {
    case "$*" in
      *workflow*)
        # Return JSON with a cleanup node in Succeeded phase
        cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {"templateName": "cleanup", "phase": "Succeeded"}
    }
  }
}
JSON
        ;;
      *pvc*)
        # PVC not found — already cleaned up
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: passes when PVC does not exist (already deleted)" {
  kubectl() {
    case "$*" in
      *workflow* | *get\ workflow*)
        cat <<'JSON'
{"status":{"nodes":{}}}
JSON
        ;;
      *pvc*)
        # PVC not found
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: passes when no cleanup node is found (skips phase check)" {
  kubectl() {
    case "$*" in
      *workflow*)
        # No cleanup node in node tree
        echo '{"status":{"nodes":{"other-node":{"templateName":"run-agent","phase":"Succeeded"}}}}'
        ;;
      *pvc*)
        # PVC not found
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: fails when cleanup node phase is Failed" {
  kubectl() {
    case "$*" in
      *workflow*)
        cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {"templateName": "cleanup", "phase": "Failed"}
    }
  }
}
JSON
        ;;
      *pvc*)
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_work_dir_clean: failure output mentions the workflow name" {
  kubectl() {
    case "$*" in
      *workflow*)
        echo '{"status":{"nodes":{"cleanup-node":{"templateName":"cleanup","phase":"Failed"}}}}'
        ;;
      *pvc*)
        echo ""
        ;;
    esac
  }
  export -f kubectl

  run assert_work_dir_clean "my-target-workflow"

  [ "$status" -ne 0 ]
  [[ "$output" == *"my-target-workflow"* ]]
}

@test "assert_work_dir_clean: uses provided namespace argument" {
  local captured_args_file="$WORK_DIR/kubectl-args.txt"

  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    case "$*" in
      *workflow*)
        echo '{"status":{"nodes":{}}}'
        ;;
      *pvc*)
        echo ""
        ;;
    esac
  }
  export -f kubectl
  export captured_args_file

  run assert_work_dir_clean "pure-agent-abcde" "my-namespace"

  [ "$status" -eq 0 ]
  grep -q "my-namespace" "$captured_args_file"
}

@test "assert_work_dir_clean: fails when kubectl command fails" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -ne 0 ]
}
