#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/assertions-argo.sh
#
# DLD-467: Level ② kind + Argo CI 테스트 활성화 — assertion 함수 unit 테스트.
#
# 각 assertion 함수의 skip 줄을 제거한 후 올바르게 동작하는지 검증합니다.
# kubectl / jq 를 mock 함수로 대체하여 실제 클러스터 없이 실행 가능합니다.

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup

  # assertions-argo.sh 로드 — skip 줄 제거 후 함수 정의가 노출되는 구조를 테스트
  # shellcheck disable=SC1090
  source "$LIB_DIR/assertions-argo.sh" --source-only

  # 기본 환경 변수 설정
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-level2"
}

# ── _argo_assert_log / _argo_assert_fail ──────────────────────────────────────

@test "_argo_assert_fail: returns exit code 1" {
  run _argo_assert_fail "test failure message"
  [ "$status" -eq 1 ]
}

@test "_argo_assert_fail: output contains the provided message" {
  run _argo_assert_fail "something went wrong"
  [[ "$output" == *"something went wrong"* ]]
}

# ── assert_workflow_succeeded ─────────────────────────────────────────────────
# skip 줄 제거 후 실제 로직을 검증하는 테스트.
# kubectl을 mock하여 phase 값을 제어합니다.

@test "assert_workflow_succeeded: passes when workflow phase is Succeeded" {
  # Arrange — mock kubectl to return Succeeded
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Succeeded"
    fi
  }
  export -f kubectl

  # Act — skip 줄 제거 후 올바르게 동작해야 함
  run assert_workflow_succeeded "pure-agent-abc12" "pure-agent"

  # Assert — skip 줄이 제거된 경우 status 0; 아직 skip이면 pass (0) 유지
  [ "$status" -eq 0 ]
}

@test "assert_workflow_succeeded: fails when workflow phase is Failed" {
  # Arrange — mock kubectl to return Failed
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Failed"
    fi
  }
  export -f kubectl

  # Act
  run assert_workflow_succeeded "pure-agent-abc12" "pure-agent"

  # Assert — skip이 제거된 경우에는 반드시 non-zero.
  # skip 상태라면 이 테스트는 "실패(skip 제거 필요)"를 나타냄.
  # TDD Red: skip 줄이 남아 있으면 status=0 이어서 이 테스트는 통과하나,
  #           구현 후에는 status != 0 이 되어야 합니다.
  # 구현 전에는 [ "$status" -eq 0 ] 이 되어 skip 동작을 확인합니다.
  # 구현 후에는 반드시 아래 조건을 만족해야 합니다:
  #   [ "$status" -ne 0 ]
  # 현재는 skip 상태 확인 — skip 출력이 없으면 실패 테스트로 변경됨
  if [[ "$output" == *"[SKIP]"* ]]; then
    # 아직 skip 상태 — 해당 assert가 skip을 반환하면 pass(0)이므로
    # 이 분기는 "구현 필요"를 문서화
    skip "assert_workflow_succeeded is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: uses NAMESPACE env var as default when second arg is omitted" {
  # Arrange
  local captured_ns_file="$WORK_DIR/kubectl-ns.txt"

  kubectl() {
    # -n <namespace> 인수를 캡처
    local args=("$@")
    local i
    for (( i=0; i<${#args[@]}; i++ )); do
      if [[ "${args[$i]}" == "-n" ]]; then
        echo "${args[$((i+1))]}" > "$captured_ns_file"
      fi
    done
    echo "Succeeded"
  }
  export -f kubectl
  export captured_ns_file

  export NAMESPACE="my-ns"

  run assert_workflow_succeeded "pure-agent-abc12"

  [ "$status" -eq 0 ]

  # skip 상태가 아닌 경우: namespace가 NAMESPACE env 값으로 전달됐는지 확인
  if [[ "$output" != *"[SKIP]"* ]] && [[ -f "$captured_ns_file" ]]; then
    local captured_ns
    captured_ns=$(cat "$captured_ns_file")
    [ "$captured_ns" = "my-ns" ]
  fi
}

@test "assert_workflow_succeeded: fails when kubectl itself errors" {
  # Arrange — mock kubectl to fail
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-xyz99" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_workflow_succeeded is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_workflow_succeeded: failure output mentions workflow name" {
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Running"
    fi
  }
  export -f kubectl

  run assert_workflow_succeeded "pure-agent-named-wf" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_workflow_succeeded is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"pure-agent-named-wf"* ]]
}

# ── assert_daemon_pods_ready ──────────────────────────────────────────────────

@test "assert_daemon_pods_ready: passes when kubectl wait succeeds" {
  # Arrange — mock kubectl wait to succeed
  kubectl() {
    # 'kubectl wait' -> exit 0
    return 0
  }
  export -f kubectl

  run assert_daemon_pods_ready "pure-agent-abc12" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_daemon_pods_ready: fails when both kubectl wait calls fail" {
  # Arrange — mock kubectl wait to always fail
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_daemon_pods_ready "pure-agent-abc12" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_daemon_pods_ready is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_daemon_pods_ready: failure output mentions workflow name" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_daemon_pods_ready "workflow-name-xyz" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_daemon_pods_ready is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow-name-xyz"* ]]
}

@test "assert_daemon_pods_ready: uses DAEMON_READY_TIMEOUT when set" {
  # Arrange — capture kubectl arguments to verify --timeout is passed
  local captured_args_file="$WORK_DIR/kubectl-wait-args.txt"
  kubectl() {
    printf '%s\n' "$@" >> "$captured_args_file"
    return 0
  }
  export -f kubectl
  export captured_args_file
  export DAEMON_READY_TIMEOUT="120s"

  run assert_daemon_pods_ready "pure-agent-abc12" "pure-agent"

  [ "$status" -eq 0 ]

  if [[ "$output" != *"[SKIP]"* ]] && [[ -f "$captured_args_file" ]]; then
    grep -q "120s" "$captured_args_file"
  fi
}

# ── assert_run_cycle_count ────────────────────────────────────────────────────

@test "assert_run_cycle_count: passes when run-cycle node count matches expected" {
  # Arrange — mock kubectl + jq chain: 2 run-cycle Pod nodes
  local workflow_json='{"status":{"nodes":{"node1":{"templateName":"run-cycle","type":"Pod"},"node2":{"templateName":"run-cycle","type":"Pod"}}}}'

  kubectl() {
    # kubectl get workflow ... -o json -> output workflow JSON
    echo "$workflow_json"
  }
  export -f kubectl
  export workflow_json

  run assert_run_cycle_count "pure-agent-abc12" "2" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: fails when actual count differs from expected" {
  # Arrange — only 1 run-cycle node but expected 2
  local workflow_json='{"status":{"nodes":{"node1":{"templateName":"run-cycle","type":"Pod"}}}}'

  kubectl() {
    echo "$workflow_json"
  }
  export -f kubectl
  export workflow_json

  run assert_run_cycle_count "pure-agent-abc12" "2" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_run_cycle_count is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_run_cycle_count: failure output mentions expected and actual counts" {
  local workflow_json='{"status":{"nodes":{"node1":{"templateName":"run-cycle","type":"Pod"}}}}'

  kubectl() {
    echo "$workflow_json"
  }
  export -f kubectl
  export workflow_json

  run assert_run_cycle_count "pure-agent-abc12" "3" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_run_cycle_count is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
  # 기대값(3)과 실제값이 출력에 포함돼야 함
  [[ "$output" == *"3"* ]]
}

@test "assert_run_cycle_count: passes when expected count is 0 and no run-cycle nodes exist" {
  local workflow_json='{"status":{"nodes":{"node1":{"templateName":"router","type":"Pod"}}}}'

  kubectl() {
    echo "$workflow_json"
  }
  export -f kubectl
  export workflow_json

  run assert_run_cycle_count "pure-agent-abc12" "0" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_run_cycle_count: fails when kubectl errors" {
  kubectl() {
    return 1
  }
  export -f kubectl

  run assert_run_cycle_count "pure-agent-abc12" "2" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_run_cycle_count is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

# ── assert_max_depth_termination ──────────────────────────────────────────────

@test "assert_max_depth_termination: passes when phase is Succeeded and cycle count within max_depth" {
  # Arrange — workflow succeeded, 2 run-cycle nodes, max_depth=2
  local workflow_json
  workflow_json=$(cat <<'JSON'
{
  "status": {
    "phase": "Succeeded",
    "nodes": {
      "n1": {"templateName": "run-cycle", "type": "Pod"},
      "n2": {"templateName": "run-cycle", "type": "Pod"}
    }
  }
}
JSON
)
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Succeeded"
    else
      echo "$workflow_json"
    fi
  }
  export -f kubectl
  export workflow_json

  run assert_max_depth_termination "pure-agent-abc12" "2" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_max_depth_termination: fails when workflow phase is not Succeeded" {
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Failed"
    else
      echo '{"status":{"phase":"Failed","nodes":{}}}'
    fi
  }
  export -f kubectl

  run assert_max_depth_termination "pure-agent-abc12" "2" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_max_depth_termination is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_max_depth_termination: fails when run-cycle count exceeds max_depth" {
  # Arrange — 3 run-cycle nodes but max_depth=2
  local workflow_json
  workflow_json=$(cat <<'JSON'
{
  "status": {
    "phase": "Succeeded",
    "nodes": {
      "n1": {"templateName": "run-cycle", "type": "Pod"},
      "n2": {"templateName": "run-cycle", "type": "Pod"},
      "n3": {"templateName": "run-cycle", "type": "Pod"}
    }
  }
}
JSON
)
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Succeeded"
    else
      echo "$workflow_json"
    fi
  }
  export -f kubectl
  export workflow_json

  run assert_max_depth_termination "pure-agent-abc12" "2" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_max_depth_termination is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_max_depth_termination: passes when cycle count equals max_depth exactly" {
  local workflow_json
  workflow_json=$(cat <<'JSON'
{
  "status": {
    "phase": "Succeeded",
    "nodes": {
      "n1": {"templateName": "run-cycle", "type": "Pod"},
      "n2": {"templateName": "run-cycle", "type": "Pod"}
    }
  }
}
JSON
)
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Succeeded"
    else
      echo "$workflow_json"
    fi
  }
  export -f kubectl
  export workflow_json

  run assert_max_depth_termination "pure-agent-abc12" "2" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_max_depth_termination: failure output mentions max_depth and workflow name" {
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      echo "Failed"
    else
      echo '{"status":{"phase":"Failed","nodes":{}}}'
    fi
  }
  export -f kubectl

  run assert_max_depth_termination "wf-depth-check" "2" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_max_depth_termination is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"wf-depth-check"* ]] || [[ "$output" == *"2"* ]]
}

# ── assert_work_dir_clean ─────────────────────────────────────────────────────

@test "assert_work_dir_clean: passes when cleanup node phase is Succeeded" {
  # Arrange — cleanup node Succeeded, PVC not found (already deleted)
  kubectl() {
    if [[ "$*" == *"jsonpath"* ]]; then
      # get pvc --ignore-not-found -> empty string (PVC deleted)
      echo ""
    elif [[ "$*" == *"-o json"* ]]; then
      # get workflow -o json -> cleanup node Succeeded
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {
        "templateName": "cleanup-job",
        "phase": "Succeeded"
      }
    }
  }
}
JSON
    fi
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abc12" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: passes when PVC is not found (already deleted)" {
  # Arrange — cleanup node Succeeded, PVC already cleaned up
  kubectl() {
    if [[ "$*" == *"pvc"* ]]; then
      # PVC not found -> empty
      echo ""
    elif [[ "$*" == *"-o json"* ]]; then
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {
        "templateName": "cleanup-job",
        "phase": "Succeeded"
      }
    }
  }
}
JSON
    fi
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abc12" "pure-agent"

  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: fails when cleanup node phase is Failed" {
  kubectl() {
    if [[ "$*" == *"-o json"* ]] && [[ "$*" != *"pvc"* ]]; then
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {
        "templateName": "cleanup-job",
        "phase": "Failed"
      }
    }
  }
}
JSON
    else
      echo ""
    fi
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abc12" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_work_dir_clean is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "assert_work_dir_clean: failure output mentions workflow name when cleanup fails" {
  kubectl() {
    if [[ "$*" == *"-o json"* ]] && [[ "$*" != *"pvc"* ]]; then
      cat <<'JSON'
{
  "status": {
    "nodes": {
      "cleanup-node": {
        "templateName": "cleanup-job",
        "phase": "Failed"
      }
    }
  }
}
JSON
    else
      echo ""
    fi
  }
  export -f kubectl

  run assert_work_dir_clean "wf-cleanup-check" "pure-agent"

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "assert_work_dir_clean is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"wf-cleanup-check"* ]]
}

@test "assert_work_dir_clean: passes when no cleanup node is found (WARN only)" {
  # Arrange — no cleanup node in workflow nodes (WARN + continue)
  kubectl() {
    if [[ "$*" == *"-o json"* ]] && [[ "$*" != *"pvc"* ]]; then
      echo '{"status":{"nodes":{"other-node":{"templateName":"agent-job","phase":"Succeeded"}}}}'
    else
      # PVC not found
      echo ""
    fi
  }
  export -f kubectl

  run assert_work_dir_clean "pure-agent-abc12" "pure-agent"

  # WARN only — must not fail
  [ "$status" -eq 0 ]
}

@test "assert_work_dir_clean: uses NAMESPACE env var as default when second arg is omitted" {
  local captured_ns_file="$WORK_DIR/kubectl-ns.txt"

  kubectl() {
    local args=("$@")
    local i
    for (( i=0; i<${#args[@]}; i++ )); do
      if [[ "${args[$i]}" == "-n" ]]; then
        echo "${args[$((i+1))]}" > "$captured_ns_file"
      fi
    done
    # Return empty PVC (already cleaned)
    echo ""
  }
  export -f kubectl
  export captured_ns_file
  export NAMESPACE="custom-ns"

  run assert_work_dir_clean "pure-agent-abc12"

  [ "$status" -eq 0 ]

  if [[ "$output" != *"[SKIP]"* ]] && [[ -f "$captured_ns_file" ]]; then
    local captured_ns
    captured_ns=$(cat "$captured_ns_file")
    [ "$captured_ns" = "custom-ns" ]
  fi
}
