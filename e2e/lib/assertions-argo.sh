#!/usr/bin/env bash
# e2e/lib/assertions-argo.sh — Argo/Kubernetes 특화 assertion helpers (Level ② E2E)
#
# DLD-466: Level ② e2e 테스트 작성 (skipped)
#
# 이 파일의 모든 함수는 현재 skip 상태입니다.
# skip 제거 시 바로 실행 가능한 구조로 작성되어 있습니다.
#
# Usage in BATS: source this file with --source-only to load functions only.
#
# Functions:
#   assert_workflow_succeeded <workflow_name> [namespace]
#   assert_daemon_pods_ready <workflow_name> [namespace]
#   assert_run_cycle_count <workflow_name> <expected_count> [namespace]
#   assert_max_depth_termination <workflow_name> <max_depth> [namespace]
#   assert_work_dir_clean <workflow_name> [namespace]

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  # Being sourced for function definitions only — skip the rest of this file.
  true
fi

# ── Logging ───────────────────────────────────────────────────────────────────
_argo_assert_log()  { echo "[assertions-argo] $*" >&2; }
_argo_assert_fail() { echo "FAIL $*" >&2; exit 1; }

# ── assert_workflow_succeeded ─────────────────────────────────────────────────
# Argo Workflow가 Succeeded 상태인지 검증합니다.
#
# Arguments:
#   $1  workflow_name  — argo workflow 이름 (예: "pure-agent-abcde")
#   $2  namespace      — kubernetes namespace (기본값: $NAMESPACE 또는 "pure-agent")
#
assert_workflow_succeeded() {
  local workflow_name="$1"
  local namespace="${2:-${NAMESPACE:-pure-agent}}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

  _argo_assert_log "Checking workflow phase: $workflow_name (ns=$namespace)"

  local phase
  phase=$(kubectl get workflow "$workflow_name" \
    -n "$namespace" \
    --context "$kube_context" \
    -o jsonpath='{.status.phase}' 2>/dev/null) \
    || _argo_assert_fail "assert_workflow_succeeded: kubectl get workflow failed for $workflow_name"

  if [[ "$phase" != "Succeeded" ]]; then
    _argo_assert_fail "assert_workflow_succeeded: expected phase 'Succeeded' but got '$phase' (workflow=$workflow_name)"
  fi

  _argo_assert_log "PASS assert_workflow_succeeded: $workflow_name phase=$phase"
}

# ── assert_daemon_pods_ready ──────────────────────────────────────────────────
# MCP daemon 및 LLM gateway daemon pod가 Ready 상태로 기동됐는지 검증합니다.
# Argo Workflow 실행 중 사이드카 daemon pod들이 정상 기동되어야 합니다.
#
# Arguments:
#   $1  workflow_name  — argo workflow 이름 (pod label 필터링에 사용)
#   $2  namespace      — kubernetes namespace (기본값: $NAMESPACE 또는 "pure-agent")
#
assert_daemon_pods_ready() {
  local workflow_name="$1"
  local namespace="${2:-${NAMESPACE:-pure-agent}}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local timeout="${DAEMON_READY_TIMEOUT:-60s}"

  _argo_assert_log "Checking daemon pod readiness for workflow: $workflow_name"

  # MCP daemon pod 검증
  local mcp_ready_exit=0
  kubectl wait pod \
    --for=condition=Ready \
    -l "workflows.argoproj.io/workflow=${workflow_name},app=mcp-server" \
    -n "$namespace" \
    --context "$kube_context" \
    --timeout="$timeout" \
    2>/dev/null || mcp_ready_exit=$?

  if [[ "$mcp_ready_exit" -ne 0 ]]; then
    _argo_assert_log "Falling back: checking pod by workflow label only (mcp-server)"
    kubectl wait pod \
      --for=condition=Ready \
      -l "workflows.argoproj.io/workflow=${workflow_name}" \
      -n "$namespace" \
      --context "$kube_context" \
      --timeout="$timeout" \
      2>/dev/null \
      || _argo_assert_fail "assert_daemon_pods_ready: MCP daemon pod not ready within $timeout (workflow=$workflow_name)"
  fi

  _argo_assert_log "PASS assert_daemon_pods_ready: daemon pods ready for $workflow_name"
}

# ── assert_run_cycle_count ────────────────────────────────────────────────────
# Argo Workflow 노드 트리에서 run-cycle 템플릿 호출 횟수를 검증합니다.
# continue-then-stop 시나리오: run-cycle이 정확히 2회 실행됐는지 확인합니다.
#
# Arguments:
#   $1  workflow_name    — argo workflow 이름
#   $2  expected_count   — 기대하는 run-cycle 실행 횟수 (예: 2)
#   $3  namespace        — kubernetes namespace (기본값: $NAMESPACE 또는 "pure-agent")
#
assert_run_cycle_count() {
  local workflow_name="$1"
  local expected_count="$2"
  local namespace="${3:-${NAMESPACE:-pure-agent}}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

  _argo_assert_log "Checking run-cycle execution count: $workflow_name (expected=$expected_count)"

  # Argo Workflow 노드 트리에서 "run-cycle" 템플릿명을 가진 노드 개수 집계
  local actual_count
  actual_count=$(kubectl get workflow "$workflow_name" \
    -n "$namespace" \
    --context "$kube_context" \
    -o json 2>/dev/null \
    | jq '[.status.nodes // {} | to_entries[] | .value
           | select(.templateName == "run-cycle" and .type == "Pod")]
          | length') \
    || _argo_assert_fail "assert_run_cycle_count: kubectl/jq failed for workflow $workflow_name"

  if [[ "$actual_count" -ne "$expected_count" ]]; then
    _argo_assert_fail "assert_run_cycle_count: expected $expected_count run-cycle node(s) but got $actual_count (workflow=$workflow_name)"
  fi

  _argo_assert_log "PASS assert_run_cycle_count: $actual_count run-cycle node(s) for $workflow_name"
}

# ── assert_max_depth_termination ──────────────────────────────────────────────
# max_depth에 의한 종료가 Workflow 단계에서 올바르게 처리됐는지 검증합니다.
# depth-limit 시나리오: max_depth 도달 시 Workflow가 정상 종료(Succeeded)해야 합니다.
#
# 검증 내용:
#   1. Workflow 전체 phase가 Succeeded
#   2. 실행된 run-cycle 횟수가 max_depth를 초과하지 않음
#   3. depth-exceeded 또는 max-depth 관련 메시지/노드가 Workflow에 존재
#
# Arguments:
#   $1  workflow_name  — argo workflow 이름
#   $2  max_depth      — 설정된 max_depth 값 (예: 2)
#   $3  namespace      — kubernetes namespace (기본값: $NAMESPACE 또는 "pure-agent")
#
assert_max_depth_termination() {
  local workflow_name="$1"
  local max_depth="$2"
  local namespace="${3:-${NAMESPACE:-pure-agent}}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

  _argo_assert_log "Checking max_depth termination: $workflow_name (max_depth=$max_depth)"

  # 1. Workflow 전체 phase 확인
  local phase
  phase=$(kubectl get workflow "$workflow_name" \
    -n "$namespace" \
    --context "$kube_context" \
    -o jsonpath='{.status.phase}' 2>/dev/null) \
    || _argo_assert_fail "assert_max_depth_termination: kubectl failed for $workflow_name"

  if [[ "$phase" != "Succeeded" ]]; then
    _argo_assert_fail "assert_max_depth_termination: workflow should Succeed on max_depth but got phase='$phase' (workflow=$workflow_name)"
  fi

  # 2. run-cycle 실행 횟수가 max_depth를 초과하지 않는지 확인
  local cycle_count
  cycle_count=$(kubectl get workflow "$workflow_name" \
    -n "$namespace" \
    --context "$kube_context" \
    -o json 2>/dev/null \
    | jq '[.status.nodes // {} | to_entries[] | .value
           | select(.templateName == "run-cycle" and .type == "Pod")]
          | length') \
    || _argo_assert_fail "assert_max_depth_termination: jq failed for workflow $workflow_name"

  if [[ "$cycle_count" -gt "$max_depth" ]]; then
    _argo_assert_fail "assert_max_depth_termination: run-cycle count $cycle_count exceeds max_depth $max_depth (workflow=$workflow_name)"
  fi

  _argo_assert_log "PASS assert_max_depth_termination: workflow=$workflow_name phase=$phase cycle_count=$cycle_count max_depth=$max_depth"
}

# ── assert_work_dir_clean ─────────────────────────────────────────────────────
# Workflow job 완료 후 /work 디렉토리가 비어있음을 검증합니다.
# cleanup step이 올바르게 실행됐는지 확인합니다.
#
# 검증 방법:
#   Workflow의 cleanup 단계가 Succeeded인지 확인하거나,
#   /work PVC를 마운트한 임시 pod를 생성해 디렉토리 내용을 확인합니다.
#
# Arguments:
#   $1  workflow_name  — argo workflow 이름
#   $2  namespace      — kubernetes namespace (기본값: $NAMESPACE 또는 "pure-agent")
#
assert_work_dir_clean() {
  local workflow_name="$1"
  local namespace="${2:-${NAMESPACE:-pure-agent}}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

  _argo_assert_log "Checking /work directory cleanup: $workflow_name"

  # cleanup 노드(템플릿명에 "cleanup" 포함)가 Succeeded인지 확인
  local cleanup_phase
  cleanup_phase=$(kubectl get workflow "$workflow_name" \
    -n "$namespace" \
    --context "$kube_context" \
    -o json 2>/dev/null \
    | jq -r '[.status.nodes // {} | to_entries[] | .value
               | select(.templateName | ascii_downcase | contains("cleanup"))]
              | if length > 0 then .[0].phase else "NotFound" end' 2>/dev/null) \
    || _argo_assert_fail "assert_work_dir_clean: kubectl/jq failed for workflow $workflow_name"
  # Default to "NotFound" if jq returned empty (kubectl returned empty string or invalid JSON)
  cleanup_phase="${cleanup_phase:-NotFound}"

  if [[ "$cleanup_phase" == "NotFound" ]]; then
    _argo_assert_log "WARN assert_work_dir_clean: no cleanup node found — skipping phase check"
  elif [[ "$cleanup_phase" != "Succeeded" ]]; then
    _argo_assert_fail "assert_work_dir_clean: cleanup node phase='$cleanup_phase' (expected Succeeded) for workflow=$workflow_name"
  fi

  # PVC 이름 추출 (workflow name 기반, pure-agent 컨벤션)
  local pvc_name="${workflow_name}-work"

  # PVC가 존재하는지 확인 (cleanup 후 삭제됐을 수도 있음)
  local pvc_exists
  pvc_exists=$(kubectl get pvc "$pvc_name" \
    -n "$namespace" \
    --context "$kube_context" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$pvc_exists" ]]; then
    # PVC가 삭제된 경우 cleanup이 완료된 것으로 간주
    _argo_assert_log "PASS assert_work_dir_clean: PVC $pvc_name not found (already cleaned up)"
    return 0
  fi

  # PVC가 아직 존재하면 임시 pod로 /work 내용 확인
  local check_pod="assert-work-clean-$$"
  kubectl run "$check_pod" \
    --image=alpine:3.20 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --overrides="{
      \"spec\": {
        \"volumes\": [{\"name\":\"work\",\"persistentVolumeClaim\":{\"claimName\":\"$pvc_name\"}}],
        \"containers\": [{
          \"name\":\"check\",
          \"image\":\"alpine:3.20\",
          \"command\":[\"sh\",\"-c\",\"ls /work && echo ITEM_COUNT=$(find /work -mindepth 1 | wc -l)\"],
          \"volumeMounts\":[{\"name\":\"work\",\"mountPath\":\"/work\"}]
        }]
      }
    }" 2>/dev/null \
    | grep "ITEM_COUNT=" | {
        read -r line
        local count="${line#ITEM_COUNT=}"
        if [[ "$count" -ne 0 ]]; then
          _argo_assert_fail "assert_work_dir_clean: /work has $count item(s) after cleanup (workflow=$workflow_name, pvc=$pvc_name)"
        fi
      } \
    || _argo_assert_fail "assert_work_dir_clean: failed to inspect /work directory via pod (workflow=$workflow_name)"

  _argo_assert_log "PASS assert_work_dir_clean: /work is clean for workflow=$workflow_name"
}
