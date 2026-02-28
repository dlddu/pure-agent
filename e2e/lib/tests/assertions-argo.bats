#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/assertions-argo.sh — DLD-467 activation checks.
#
# These tests verify two things:
#
# 1. Static analysis: none of the five assertion functions contain the [SKIP]
#    guard line that disabled them in DLD-466.  Once a function's skip line is
#    removed the function body must execute instead of returning immediately.
#
# 2. Structural smoke tests: when sourced in --source-only mode the functions
#    are callable and exhibit the expected basic behaviour (e.g. fail when
#    kubectl is unavailable or args are wrong).
#
# Note: these tests do NOT require a live Kubernetes cluster.  Functions that
# call kubectl are expected to fail at the kubectl invocation, not at the
# [SKIP] guard.

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_assertions_argo
  ASSERTIONS_ARGO_FILE="${REPO_ROOT}/e2e/lib/assertions-argo.sh"
}

# ── Static: [SKIP] guard removal ─────────────────────────────────────────────

@test "assertions-argo: assert_workflow_succeeded does not contain [SKIP] guard" {
  # After DLD-467, the echo "[SKIP] ..." && return 0 line must be removed.
  run grep -n "\[SKIP\].*assert_workflow_succeeded" "$ASSERTIONS_ARGO_FILE"
  [ "$status" -ne 0 ]
}

@test "assertions-argo: assert_daemon_pods_ready does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*assert_daemon_pods_ready" "$ASSERTIONS_ARGO_FILE"
  [ "$status" -ne 0 ]
}

@test "assertions-argo: assert_run_cycle_count does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*assert_run_cycle_count" "$ASSERTIONS_ARGO_FILE"
  [ "$status" -ne 0 ]
}

@test "assertions-argo: assert_max_depth_termination does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*assert_max_depth_termination" "$ASSERTIONS_ARGO_FILE"
  [ "$status" -ne 0 ]
}

@test "assertions-argo: assert_work_dir_clean does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*assert_work_dir_clean" "$ASSERTIONS_ARGO_FILE"
  [ "$status" -ne 0 ]
}

@test "assertions-argo: file contains no [SKIP] patterns at all" {
  run grep -c "\[SKIP\]" "$ASSERTIONS_ARGO_FILE"
  # grep -c returns 0 matches → exit 1; we want exit 1 (no matches found)
  [ "$status" -ne 0 ]
}

# ── Structural: functions are defined and callable ────────────────────────────

@test "assertions-argo: assert_workflow_succeeded function is defined after sourcing" {
  run bash -c "
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    declare -f assert_workflow_succeeded > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "assertions-argo: assert_daemon_pods_ready function is defined after sourcing" {
  run bash -c "
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    declare -f assert_daemon_pods_ready > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "assertions-argo: assert_run_cycle_count function is defined after sourcing" {
  run bash -c "
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    declare -f assert_run_cycle_count > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "assertions-argo: assert_max_depth_termination function is defined after sourcing" {
  run bash -c "
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    declare -f assert_max_depth_termination > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "assertions-argo: assert_work_dir_clean function is defined after sourcing" {
  run bash -c "
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    declare -f assert_work_dir_clean > /dev/null
  "
  [ "$status" -eq 0 ]
}

# ── Structural: functions fail (non-zero) when kubectl is unavailable ─────────
# After the skip lines are removed the functions must attempt real kubectl
# calls.  We mock kubectl to fail so the assertion functions exit non-zero.

@test "assert_workflow_succeeded: fails when kubectl is unavailable" {
  # Arrange — override kubectl to simulate absence
  kubectl() { return 127; }
  export -f kubectl

  run bash -c "
    kubectl() { return 127; }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_workflow_succeeded 'fake-workflow-name' 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

@test "assert_run_cycle_count: fails when kubectl is unavailable" {
  run bash -c "
    kubectl() { return 127; }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_run_cycle_count 'fake-workflow' 2 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

@test "assert_max_depth_termination: fails when kubectl is unavailable" {
  run bash -c "
    kubectl() { return 127; }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_max_depth_termination 'fake-workflow' 3 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

@test "assert_work_dir_clean: fails when kubectl is unavailable" {
  run bash -c "
    kubectl() { return 127; }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_work_dir_clean 'fake-workflow' 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

# ── Structural: assert_workflow_succeeded checks phase from kubectl output ─────

@test "assert_workflow_succeeded: passes when kubectl returns Succeeded phase" {
  run bash -c "
    kubectl() {
      # Simulate: kubectl get workflow ... -o jsonpath='{.status.phase}'
      echo 'Succeeded'
      return 0
    }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_workflow_succeeded 'mock-workflow' 'pure-agent'
  "
  [ "$status" -eq 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Failed" {
  run bash -c "
    kubectl() {
      echo 'Failed'
      return 0
    }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_workflow_succeeded 'mock-workflow' 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: failure output mentions expected phase Succeeded" {
  run bash -c "
    kubectl() { echo 'Running'; return 0; }
    export -f kubectl
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_workflow_succeeded 'mock-workflow' 'pure-agent'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Succeeded"* ]]
}

# ── Structural: assert_run_cycle_count numeric comparison ─────────────────────

@test "assert_run_cycle_count: passes when kubectl+jq returns the expected count" {
  run bash -c "
    kubectl() { echo '{}'; return 0; }
    jq() { echo '2'; return 0; }
    export -f kubectl jq
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_run_cycle_count 'mock-workflow' 2 'pure-agent'
  "
  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: fails when actual count differs from expected" {
  run bash -c "
    kubectl() { echo '{}'; return 0; }
    jq() { echo '1'; return 0; }
    export -f kubectl jq
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_run_cycle_count 'mock-workflow' 2 'pure-agent'
  "
  [ "$status" -ne 0 ]
}

@test "assert_run_cycle_count: failure output mentions expected and actual counts" {
  run bash -c "
    kubectl() { echo '{}'; return 0; }
    jq() { echo '1'; return 0; }
    export -f kubectl jq
    source '${REPO_ROOT}/e2e/lib/assertions-argo.sh' --source-only
    assert_run_cycle_count 'mock-workflow' 3 'pure-agent'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"3"* ]]
}
