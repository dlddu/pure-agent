#!/usr/bin/env bash
# e2e/run-integration.sh — Integration E2E 테스트 러너 (kind + Argo, mock 기반)
#
# Mock:
#   - Agent        → mock-agent (ConfigMap에서 fixture를 읽어 시뮬레이션)
#   - Linear API   → mock-api (클러스터 내 GraphQL mock 서비스)
#   - GitHub CLI   → mock (Workflow 내 passthrough)
#   - Planner      → mock-planner (Alpine 스크립트, prompt에서 env 파싱)
#   - Gate         → mock-gate (Alpine 스크립트, depth limit 로직만 구현)
#   - Export Handler → mock (passthrough)
#   - Anthropic API → 사용하지 않음
#   - MCP daemon / LLM gateway → 사용하지 않음
# Real:
#   - Argo Workflows (WorkflowTemplate 제출, 대기, 상태 확인)
#   - Kubernetes    (kind 클러스터, ConfigMap, Pod lifecycle)
#
# 시나리오 정의는 e2e/scenarios/<name>.yaml 파일에서 읽습니다.
# cycles[] 배열의 각 cycle을 독립적인 Argo Workflow로 제출하고,
# mock-agent가 ConfigMap에서 fixture를 읽어 시뮬레이션합니다.
#
# Usage:
#   ./e2e/run-integration.sh [--scenario <name|all>] [--namespace <ns>] [--context <ctx>]
#
# Environment variables:
#   SCENARIO          — 실행할 시나리오 이름 (기본값: all)
#   NAMESPACE         — Kubernetes 네임스페이스 (기본값: pure-agent)
#   KUBE_CONTEXT      — kubectl context (기본값: kind-pure-agent-e2e-integration)
#   MOCK_AGENT_IMAGE  — mock-agent 이미지 (기본값: ghcr.io/dlddu/pure-agent/e2e/mock-agent:latest)
#   MOCK_API_URL      — mock-api 서비스 URL
#   WORKFLOW_TIMEOUT   — Workflow 대기 타임아웃 초 (기본값: 600)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-2}"
NAMESPACE="${NAMESPACE:-pure-agent}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"
MOCK_AGENT_IMAGE="${MOCK_AGENT_IMAGE:-ghcr.io/dlddu/pure-agent/e2e/mock-agent:latest}"
MOCK_API_URL="${MOCK_API_URL:-http://mock-api.${NAMESPACE}.svc.cluster.local:4000}"

# ── Source shared libraries ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/assertions-argo.sh
source "$LIB_DIR/assertions-argo.sh" --source-only
# shellcheck source=lib/localstack.sh
source "$LIB_DIR/localstack.sh" --source-only

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[run-integration] $*" >&2; }
warn() { echo "[run-integration] WARN: $*" >&2; }
die()  { echo "[run-integration] ERROR: $*" >&2; exit 1; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
__SOURCE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-only) __SOURCE_ONLY=true; shift ;;
    --scenario)    SCENARIO="$2";   shift 2 ;;
    --namespace)   NAMESPACE="$2";  shift 2 ;;
    --context)     KUBE_CONTEXT="$2"; shift 2 ;;
    *)             die "Unknown argument: $1" ;;
  esac
done

# ── S3 secret management ────────────────────────────────────────────────────
# Creates or patches the gate-secrets Secret so the gate container in the
# Argo Workflow can upload transcripts to the LocalStack S3 endpoint.
_ensure_gate_s3_secret() {
  log "Ensuring gate-secrets with LocalStack S3 config"
  kubectl create secret generic gate-secrets \
    --from-literal=AWS_S3_BUCKET_NAME="$S3_TEST_BUCKET" \
    --from-literal=AWS_ENDPOINT_URL="$S3_ENDPOINT_URL" \
    --from-literal=AWS_ACCESS_KEY_ID="test" \
    --from-literal=AWS_SECRET_ACCESS_KEY="test" \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    --dry-run=client -o yaml \
    | kubectl apply -f - -n "$NAMESPACE" --context "$KUBE_CONTEXT" >&2
  log "gate-secrets configured for LocalStack"
}

# ── Prerequisites check ─────────────────────────────────────────────────────
check_prerequisites() {
  command -v argo    >/dev/null 2>&1 || { die "argo CLI is not installed"; return 1; }
  command -v kubectl >/dev/null 2>&1 || { die "kubectl is not installed"; return 1; }
  command -v jq      >/dev/null 2>&1 || { die "jq is not installed"; return 1; }
  command -v yq      >/dev/null 2>&1 || { die "yq is not installed"; return 1; }

  log "Prerequisites OK"
}

# ═══════════════════════════════════════════════════════════════════════════════
# WORKFLOW FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# submit_mock_workflow: mock-agent를 사용하여 Argo Workflow를 제출합니다.
# SCENARIO_DIR ConfigMap을 생성하고 Workflow를 제출합니다.
#
# Arguments:
#   $1  scenario_name  — 시나리오 이름
#   $2  cycle_index    — cycle 인덱스
#   $3  max_depth      — 최대 depth (기본값: 5)
#   $4  scenario_dir   — fixture 파일 디렉토리
#   $5  env_id         — environment_id (mock-planner가 prompt에서 파싱)
#
# 출력: workflow name
#
submit_mock_workflow() {
  local scenario_name="$1"
  local cycle_index="$2"
  local max_depth="${3:-5}"
  local scenario_dir="$4"
  local env_id="${5:-default}"

  local cm_name="mock-scenario-${scenario_name}-cycle${cycle_index}-$$"
  local cm_name_safe
  # ConfigMap 이름은 소문자 + 숫자 + 하이픈만 허용
  cm_name_safe=$(echo "$cm_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | cut -c1-253)

  log "Creating ConfigMap '$cm_name_safe' for scenario fixtures"

  # ConfigMap 생성 (export_config.json, agent_result.txt를 데이터로 포함)
  local cm_from_args=()
  if [[ -f "${scenario_dir}/export_config.json" ]]; then
    cm_from_args+=(--from-file=export_config.json="${scenario_dir}/export_config.json")
  fi
  if [[ -f "${scenario_dir}/agent_result.txt" ]]; then
    cm_from_args+=(--from-file=agent_result.txt="${scenario_dir}/agent_result.txt")
  fi

  if [[ "${#cm_from_args[@]}" -gt 0 ]]; then
    kubectl create configmap "$cm_name_safe" \
      "${cm_from_args[@]}" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" \
      --dry-run=client -o yaml \
      | kubectl apply -f - -n "$NAMESPACE" --context "$KUBE_CONTEXT" >&2
  else
    # 빈 ConfigMap 생성 (depth-limit 시나리오처럼 export_config가 null인 경우)
    kubectl create configmap "$cm_name_safe" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" \
      --dry-run=client -o yaml \
      | kubectl apply -f - -n "$NAMESPACE" --context "$KUBE_CONTEXT" >&2
  fi

  log "Submitting mock Argo Workflow (scenario=$scenario_name, cycle=$cycle_index, max_depth=$max_depth)"

  # Argo Workflow 제출 — mock-agent 이미지와 SCENARIO_DIR(ConfigMap 마운트)를 사용
  local submit_output
  submit_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="[mock] scenario=${scenario_name} cycle=${cycle_index} env=${env_id}" \
    -p mock_api_url="$MOCK_API_URL" \
    -p scenario_configmap="$cm_name_safe" \
    --output json 2>&1) || {
      warn "Argo workflow submission failed (scenario=$scenario_name, cycle=$cycle_index):"
      echo "$submit_output" >&2
      die "Workflow submission failed for: $scenario_name cycle $cycle_index"
    }

  local workflow_name
  workflow_name=$(echo "$submit_output" | jq -r '.metadata.name')
  log "Submitted mock workflow: $workflow_name"

  # Workflow 완료 대기
  local wait_exit=0
  timeout "${WORKFLOW_TIMEOUT}s" \
    argo wait "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" >&2 || wait_exit=$?

  if [[ "$wait_exit" -ne 0 ]]; then
    local phase
    phase=$(argo get "$workflow_name" -n "$NAMESPACE" --context "$KUBE_CONTEXT" \
      --output json 2>/dev/null | jq -r '.status.phase // "Unknown"')
    if [[ "$wait_exit" -eq 124 ]]; then
      warn "Mock workflow timed out after ${WORKFLOW_TIMEOUT}s: $workflow_name (phase=$phase)"
    else
      warn "argo wait failed (exit=$wait_exit): $workflow_name (phase=$phase)"
    fi
    argo get "$workflow_name" -n "$NAMESPACE" --context "$KUBE_CONTEXT" >&2 || true
    die "Mock workflow failed: $scenario_name cycle $cycle_index"
  fi

  echo "$workflow_name"
}

# verify_cycle: 단일 cycle 검증 (assertions 필드 기반)
#
# Arguments:
#   $1  yaml_file      — 시나리오 YAML 파일 경로
#   $2  workflow_name  — 완료된 workflow 이름
#   $3  cycle_index    — 검증 중인 cycle 인덱스
#
verify_cycle() {
  local yaml_file="$1"
  local workflow_name="$2"
  local cycle_index="$3"

  log "Verifying cycle ${cycle_index} for workflow: $workflow_name"

  # 1. Workflow Succeeded 검증
  assert_workflow_succeeded "$workflow_name" "$NAMESPACE" || return 1

  # 2. Planner image assertion
  local planner_image
  planner_image=$(yaml_get "$yaml_file" '.assertions.planner_image')
  if [[ -n "$planner_image" ]]; then
    assert_planner_image "$workflow_name" "$planner_image" "$NAMESPACE" || return 1
  fi

  # 3. mock-api 기반 assertion은 skip
  # mock-agent는 HTTP 호출을 하지 않으므로 mock-api에 recorded call이 없음.
  # gate_decision은 assert_run_cycle_count / assert_workflow_succeeded로 간접 검증.
  log "Skipping mock-api assertions (not applicable in Integration mock architecture)"

  # 4. S3 transcript upload 검증
  if [[ -n "${S3_ENDPOINT_URL:-}" ]]; then
    log "Verifying S3 transcript upload for cycle ${cycle_index}"
    assert_s3_transcript_exists 1 || return 1
  fi

  log "Cycle ${cycle_index} verification passed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCENARIO RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

# run_scenario: cycles[]를 순회하며 mock-agent 방식으로 실행하고 검증합니다.
#
# Arguments:
#   $1  scenario_name  — 시나리오 이름
#
run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== Integration Scenario: $scenario_name ==="

  # cycles 배열 길이 확인
  local cycle_count
  cycle_count=$(yq eval '.cycles | length' "$yaml_file" 2>/dev/null || echo "0")

  if [[ "$cycle_count" -eq 0 ]]; then
    warn "No cycles defined in scenario: $scenario_name — skipping"
    return 0
  fi

  # max_depth 읽기 (시나리오 레벨 또는 기본값 5)
  local max_depth
  max_depth=$(yaml_get "$yaml_file" '.max_depth // 5')

  # 각 cycle을 독립적인 Workflow로 제출하고 검증합니다.
  local cycle_index
  local all_workflow_names=()

  for (( cycle_index=0; cycle_index<cycle_count; cycle_index++ )); do
    log "--- Cycle ${cycle_index}/${cycle_count} ---"

    # per-cycle max_depth (YAML에서 cycles[i].max_depth를 확인, 없으면 시나리오 max_depth)
    local cycle_max_depth
    cycle_max_depth=$(yaml_get "$yaml_file" ".cycles[${cycle_index}].max_depth")
    if [[ -z "$cycle_max_depth" ]]; then
      cycle_max_depth="$max_depth"
    fi

    # 임시 fixture 디렉토리 생성
    local cycle_dir
    cycle_dir=$(mktemp -d "/tmp/e2e-integration-${scenario_name}-cycle${cycle_index}-XXXXXX")

    # environment_id 읽기 (mock-planner가 prompt에서 파싱)
    local env_id
    env_id=$(yaml_get "$yaml_file" ".cycles[${cycle_index}].environment_id")

    # cycle fixtures 배치
    prepare_cycle_fixtures "$yaml_file" "$cycle_index" "$cycle_dir"

    # mock Argo Workflow 제출 + 완료 대기
    local workflow_name
    workflow_name=$(submit_mock_workflow \
      "$scenario_name" "$cycle_index" "$cycle_max_depth" "$cycle_dir" "$env_id")

    all_workflow_names+=("$workflow_name")

    # cycle 검증
    verify_cycle "$yaml_file" "$workflow_name" "$cycle_index"

    # 임시 디렉토리 정리
    rm -rf "$cycle_dir"
  done

  # --- 시나리오 레벨 추가 검증 ---

  # continue-then-stop: 전체 cycle 수만큼 workflow가 실행됐는지 검증
  local scenario_name_check
  scenario_name_check=$(yaml_get "$yaml_file" '.name')
  if [[ "$scenario_name_check" == "continue-then-stop" ]]; then
    log "continue-then-stop: verifying workflow count matches cycle count"
    local wf_count="${#all_workflow_names[@]}"
    if [[ "$wf_count" -ne "$cycle_count" ]]; then
      die "continue-then-stop: expected $cycle_count workflows but got $wf_count"
    fi
    for wf_name in "${all_workflow_names[@]}"; do
      assert_run_cycle_count "$wf_name" 1 "$NAMESPACE"
    done
  fi

  # depth-limit: max_depth 종료 검증
  if [[ "$scenario_name_check" == "depth-limit" ]]; then
    log "depth-limit: verifying max_depth termination"
    local last_workflow="${all_workflow_names[${#all_workflow_names[@]}-1]}"
    assert_max_depth_termination "$last_workflow" "$max_depth" "$NAMESPACE"
  fi

  # daemon pods ready / work dir cleanup 검증
  # mock-agent만 실행되며 MCP daemon/LLM gateway 사이드카가 없으므로 skip.
  log "Skipping daemon_pods_ready and work_dir_clean assertions (Integration mock architecture)"

  log "=== PASS (Integration): $scenario_name ==="
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log "Starting Integration E2E test runner (kind + Argo, mock)"
  log "SCENARIO=${SCENARIO}, NAMESPACE=${NAMESPACE}"

  check_prerequisites

  # Deploy LocalStack for S3 transcript upload verification
  deploy_localstack
  wait_localstack
  create_s3_test_bucket

  # Set S3 env vars for workflows to use LocalStack
  export S3_ENDPOINT_URL
  S3_ENDPOINT_URL=$(localstack_endpoint_url)
  export S3_TEST_BUCKET

  # Create/update gate-secrets with LocalStack S3 configuration
  _ensure_gate_s3_secret

  trap 'teardown_localstack' EXIT

  if [[ "$SCENARIO" == "all" ]]; then
    local scenarios
    scenarios=$(discover_scenarios)
    [[ -n "$scenarios" ]] \
      || die "No Integration scenarios found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All Integration scenarios completed"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "$__SOURCE_ONLY" == "true" ]]; then
  return 0 2>/dev/null || true
fi

main "$@"
