#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for tests/lib/assertions-argo.sh
#
# TDD Red Phase: the functions under test currently return 0 immediately via
# "[SKIP] ... && return 0" guards.  These tests will all FAIL until the skip
# guards are removed and the real logic is implemented (DLD-466).

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_assertions_argo
}

# ── Helper: fake kubectl ───────────────────────────────────────────────────────
# Tests override `kubectl` with a shell function that returns controlled JSON.
# The function is exported so subshells (run …) can see it.

# ── assert_workflow_succeeded ──────────────────────────────────────────────────

@test "assert_workflow_succeeded: passes when workflow phase is Succeeded" {
  # Arrange — mock kubectl to report phase=Succeeded
  kubectl() {
    echo "Succeeded"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"
  export NAMESPACE="pure-agent"

  # Act
  run assert_workflow_succeeded "pure-agent-abcde"

  # Assert
  [ "$status" -eq 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Failed" {
  # Arrange
  kubectl() {
    echo "Failed"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"
  export NAMESPACE="pure-agent"

  # Act
  run assert_workflow_succeeded "pure-agent-abcde"

  # Assert
  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Running" {
  # Arrange
  kubectl() {
    echo "Running"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Error" {
  # Arrange
  kubectl() {
    echo "Error"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: fails when kubectl returns empty phase" {
  # Arrange — simulate kubectl failure (no output)
  kubectl() {
    return 1
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_workflow_succeeded "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: failure output mentions expected phase Succeeded" {
  # Arrange
  kubectl() {
    echo "Failed"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_workflow_succeeded "my-workflow"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Succeeded"* ]]
}

@test "assert_workflow_succeeded: failure output mentions actual phase" {
  # Arrange
  kubectl() {
    echo "Error"
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_workflow_succeeded "my-workflow"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

@test "assert_workflow_succeeded: uses namespace argument when provided" {
  # Arrange — capture kubectl args to verify -n flag is used
  local captured_args_file="$WORK_DIR/kubectl-args.txt"
  touch "$captured_args_file"

  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    echo "Succeeded"
  }
  export -f kubectl
  export captured_args_file
  export KUBE_CONTEXT="kind-test"

  # Act — run without `run` so kubectl mock writes to captured_args_file in the
  # same shell process (not a subshell where path resolution may differ).
  assert_workflow_succeeded "my-workflow" "custom-ns"

  # Assert
  grep -q "custom-ns" "$captured_args_file"
}

@test "assert_workflow_succeeded: defaults namespace to NAMESPACE env var" {
  # Arrange
  local captured_args_file="$WORK_DIR/kubectl-args.txt"
  touch "$captured_args_file"

  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    echo "Succeeded"
  }
  export -f kubectl
  export captured_args_file
  export NAMESPACE="my-default-ns"
  export KUBE_CONTEXT="kind-test"

  # Act — call directly (not via `run`) to stay in the same shell process
  assert_workflow_succeeded "my-workflow"

  # Assert
  grep -q "my-default-ns" "$captured_args_file"
}

# ── assert_daemon_pods_ready ───────────────────────────────────────────────────

@test "assert_daemon_pods_ready: passes when kubectl wait returns 0" {
  # Arrange — mock kubectl wait to succeed immediately
  kubectl() {
    # Simulate: kubectl wait pod ... returns 0
    return 0
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"
  export NAMESPACE="pure-agent"

  run assert_daemon_pods_ready "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_daemon_pods_ready: fails when both kubectl wait calls fail" {
  # Arrange — simulate both pod wait calls failing
  kubectl() {
    return 1
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_daemon_pods_ready "pure-agent-abcde"

  [ "$status" -ne 0 ]
}

@test "assert_daemon_pods_ready: uses provided namespace argument" {
  # Arrange — capture args to verify namespace; call directly (not via `run`)
  # so the mock function writes to the captured_args_file in the same process.
  local captured_args_file="$WORK_DIR/kubectl-args.txt"
  touch "$captured_args_file"

  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    return 0
  }
  export -f kubectl
  export captured_args_file
  export KUBE_CONTEXT="kind-test"

  # Act
  assert_daemon_pods_ready "my-workflow" "special-ns"

  # Assert
  grep -q "special-ns" "$captured_args_file"
}

# ── assert_work_dir_clean ──────────────────────────────────────────────────────

@test "assert_work_dir_clean: passes when cleanup node phase is Succeeded" {
  # Arrange — workflow JSON with a cleanup node that Succeeded
  local call_count_file="$WORK_DIR/kubectl-calls.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"
    if [[ "$n" -eq 1 ]]; then
      # First call: get workflow JSON for cleanup node phase
      cat <<'JSON'
{"status":{"nodes":{"n1":{"templateName":"cleanup","phase":"Succeeded"}}}}
JSON
    else
      # Subsequent calls: PVC not found (already cleaned up)
      echo ""
    fi
  }
  export -f kubectl
  export call_count_file
  export KUBE_CONTEXT="kind-test"
  export NAMESPACE="pure-agent"

  run assert_work_dir_clean "pure-agent-abcde"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: passes when PVC is not found (already deleted)" {
  # Arrange — no cleanup node, PVC also absent
  local call_count_file="$WORK_DIR/kubectl-calls.txt"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"
    if [[ "$n" -eq 1 ]]; then
      # Workflow JSON: no cleanup node
      echo '{"status":{"nodes":{}}}'
    else
      # PVC check: not found
      echo ""
    fi
  }
  export -f kubectl
  export call_count_file
  export KUBE_CONTEXT="kind-test"

  run assert_work_dir_clean "my-wf"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: fails when cleanup node phase is not Succeeded" {
  # Arrange — cleanup node exists but phase is Failed
  kubectl() {
    cat <<'JSON'
{"status":{"nodes":{"n1":{"templateName":"cleanup","phase":"Failed"}}}}
JSON
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_work_dir_clean "my-wf"

  [ "$status" -ne 0 ]
}

@test "assert_work_dir_clean: failure output mentions cleanup or work directory" {
  # Arrange
  kubectl() {
    cat <<'JSON'
{"status":{"nodes":{"n1":{"templateName":"cleanup","phase":"Failed"}}}}
JSON
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_work_dir_clean "my-wf"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cleanup"* ]] || [[ "$output" == *"/work"* ]] || [[ "$output" == *"Failed"* ]]
}

@test "assert_work_dir_clean: fails when kubectl call fails" {
  # Arrange
  kubectl() {
    return 1
  }
  export -f kubectl
  export KUBE_CONTEXT="kind-test"

  run assert_work_dir_clean "my-wf"

  [ "$status" -ne 0 ]
}

@test "assert_work_dir_clean: uses provided namespace argument" {
  # Arrange — call directly (not via `run`) so mock writes to the shared file
  local captured_args_file="$WORK_DIR/kubectl-args.txt"
  local call_count_file="$WORK_DIR/kubectl-calls.txt"
  touch "$captured_args_file"
  echo "0" > "$call_count_file"

  kubectl() {
    local n
    n=$(cat "$call_count_file")
    n=$((n + 1))
    echo "$n" > "$call_count_file"
    printf '%s\n' "$@" >> "$captured_args_file"
    if [[ "$n" -eq 1 ]]; then
      echo '{"status":{"nodes":{}}}'
    else
      echo ""
    fi
  }
  export -f kubectl
  export captured_args_file
  export call_count_file
  export KUBE_CONTEXT="kind-test"

  # Act
  assert_work_dir_clean "my-wf" "override-ns"

  # Assert
  grep -q "override-ns" "$captured_args_file"
}
