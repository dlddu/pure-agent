#!/usr/bin/env bash
# e2e/run-argo.sh — Level ② / Level ③ E2E runner: kind + Argo
#
# DLD-465: Level ③ 풀 e2e를 실제로 동작하게 구현.
# DLD-466: Level ② e2e 테스트 작성 (skipped) — mock-agent + mock-api 기반.
#
# 시나리오 정의는 e2e/scenarios/<name>.yaml 파일에서 읽습니다.
# YAML의 real.setup/teardown/max_depth 및 assertions 섹션을 사용하여
# 제네릭하게 시나리오를 실행합니다.
#
# Usage:
#   ./e2e/run-argo.sh [--scenario <name|all>] [--level <2|3>] [--namespace <ns>]
#
# Environment variables (Level ③, required):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)
#
# Environment variables (Level ②, required):
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-level2)
#   MOCK_AGENT_IMAGE      — mock-agent 이미지 (기본값: ghcr.io/dlddu/pure-agent/mock-agent:latest)
#   MOCK_API_URL          — mock-api 서비스 URL (기본값: http://mock-api.pure-agent.svc.cluster.local:4000)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-3}"
NAMESPACE="${NAMESPACE:-pure-agent}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds
GITHUB_TEST_BRANCH_PREFIX="e2e-test"

# Level ② 전용 설정 (arg parsing 전 환경 변수 기반 기본값 설정)
MOCK_AGENT_IMAGE="${MOCK_AGENT_IMAGE:-ghcr.io/dlddu/pure-agent/mock-agent:latest}"
MOCK_API_URL="${MOCK_API_URL:-http://mock-api.${NAMESPACE}.svc.cluster.local:4000}"

# ── Source shared libraries ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
# shellcheck source=lib/setup-real.sh
source "$LIB_DIR/setup-real.sh" --source-only
# shellcheck source=lib/teardown-real.sh
source "$LIB_DIR/teardown-real.sh" --source-only
# shellcheck source=lib/verify-real.sh
source "$LIB_DIR/verify-real.sh" --source-only
# shellcheck source=lib/assertions-argo.sh
source "$LIB_DIR/assertions-argo.sh" --source-only

# ── Logging (override library prefixes) ──────────────────────────────────────
log()  { echo "[run-argo] $*" >&2; }
warn() { echo "[run-argo] WARN: $*" >&2; }
die()  { echo "[run-argo] ERROR: $*" >&2; exit 1; }

# ── Source guard (must be before arg parsing) ────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || true
fi

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="$2";   shift 2 ;;
    --level)      LEVEL="$2";      shift 2 ;;
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --context)    KUBE_CONTEXT="$2"; shift 2 ;;
    *)            die "Unknown argument: $1" ;;
  esac
done

# ── Level별 kube context 및 필수 변수 설정 (arg parsing 후) ─────────────────
# Level ②: GITHUB_TEST_REPO 불필요, kube context 기본값 다름
if [[ "${LEVEL}" == "2" ]]; then
  KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
else
  KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
  # Level ③은 GITHUB_TEST_REPO 필수
  GITHUB_TEST_REPO="${GITHUB_TEST_REPO:?GITHUB_TEST_REPO is not set}"
fi

# ── Prerequisites check ──────────────────────────────────────────────────────
check_prerequisites() {
  if [[ "${LEVEL}" == "2" ]]; then
    # TODO: Activate when DLD-466 is implemented (remove the skip line below)
    # Level ② prerequisites: kind/kubectl/argo/jq/yq のみ確認。
    # LINEAR_API_KEY / GITHUB_TOKEN は不要。
    echo "[SKIP] check_prerequisites (Level 2): Not yet implemented (DLD-466)" && return 0

    command -v argo    >/dev/null 2>&1 || die "argo CLI is not installed"
    command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"
    command -v jq      >/dev/null 2>&1 || die "jq is not installed"
    command -v yq      >/dev/null 2>&1 || die "yq is not installed"

    log "Prerequisites OK (Level 2)"
  else
    # Level ③: 실제 API 키 및 curl 필요
    command -v argo    >/dev/null 2>&1 || die "argo CLI is not installed"
    command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"
    command -v curl    >/dev/null 2>&1 || die "curl is not installed"
    command -v jq      >/dev/null 2>&1 || die "jq is not installed"
    command -v yq      >/dev/null 2>&1 || die "yq is not installed"

    [[ -n "${LINEAR_API_KEY:-}" ]]  || die "LINEAR_API_KEY is not set"
    [[ -n "${LINEAR_TEAM_ID:-}" ]]  || die "LINEAR_TEAM_ID is not set"
    [[ -n "${GITHUB_TOKEN:-}" ]]    || die "GITHUB_TOKEN is not set"

    log "Prerequisites OK (Level 3)"
  fi
}

# ── YAML helper ──────────────────────────────────────────────────────────────
# yq wrapper with null → empty string conversion.
yaml_get() {
  local yaml_file="$1"
  local path="$2"
  local value
  value=$(yq eval "$path" "$yaml_file")
  if [[ "$value" == "null" ]]; then
    echo ""
  else
    echo "$value"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# build_prompt: 시나리오 YAML의 real.prompt를 읽고 변수를 치환합니다.
build_prompt() {
  local yaml_file="$1"
  local linear_issue_id="${2:-}"
  local github_branch="${3:-}"

  local prompt
  prompt=$(yaml_get "$yaml_file" '.real.prompt')
  [[ -n "$prompt" ]] \
    || die "Prompt not defined in: $yaml_file (real.prompt)"

  # 변수 치환
  prompt="${prompt//\{\{LINEAR_ISSUE_ID\}\}/$linear_issue_id}"
  prompt="${prompt//\{\{GITHUB_TEST_REPO\}\}/$GITHUB_TEST_REPO}"
  prompt="${prompt//\{\{GITHUB_BRANCH\}\}/$github_branch}"

  echo "$prompt"
}

# run_argo_workflow: Argo Workflow를 제출하고 완료까지 대기합니다.
# 출력: workflow name (예: "pure-agent-abcde")
run_argo_workflow() {
  local scenario_name="$1"
  local prompt="$2"
  local max_depth="${3:-5}"

  log "Submitting Argo Workflow for scenario: $scenario_name"
  log "Prompt: $prompt"

  local submit_output
  submit_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="$prompt" \
    --output json 2>&1) || {
      warn "Argo workflow submission failed:"
      echo "$submit_output" >&2
      die "Workflow failed for scenario: $scenario_name"
    }

  local workflow_name
  workflow_name=$(echo "$submit_output" | jq -r '.metadata.name')
  log "Submitted workflow: $workflow_name — waiting up to ${WORKFLOW_TIMEOUT}s"

  local wait_exit=0
  timeout "${WORKFLOW_TIMEOUT}s" \
    argo wait "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" || wait_exit=$?

  # Always fetch workflow status for diagnostics
  local workflow_output
  workflow_output=$(argo get "$workflow_name" \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    --output json 2>&1) || true

  local workflow_phase
  workflow_phase=$(echo "$workflow_output" | jq -r '.status.phase // "Unknown"')

  if [[ "$wait_exit" -ne 0 ]]; then
    if [[ "$wait_exit" -eq 124 ]]; then
      warn "Workflow timed out after ${WORKFLOW_TIMEOUT}s: $workflow_name (phase=$workflow_phase)"
    else
      warn "argo wait failed (exit=$wait_exit) for: $workflow_name (phase=$workflow_phase)"
    fi
    # Dump workflow node tree for debugging
    log "=== Workflow status ==="
    argo get "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" 2>&1 >&2 || true
    log "=== Pod status ==="
    kubectl get pods \
      -l "workflows.argoproj.io/workflow=$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" \
      -o wide 2>&1 >&2 || true
    log "=== Workflow logs (last 200 lines) ==="
    argo logs "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" 2>&1 | tail -200 >&2 || true
    log "=== End diagnostics ==="
    die "Workflow failed for scenario: $scenario_name"
  fi

  log "Workflow completed: name=$workflow_name phase=$workflow_phase"

  [[ "$workflow_phase" == "Succeeded" ]] \
    || die "Workflow did not succeed (phase=$workflow_phase) for scenario: $scenario_name"

  echo "$workflow_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LEVEL ② RUNNER (DLD-466 — skip 상태)
# ═══════════════════════════════════════════════════════════════════════════════

# _level2_place_cycle_fixtures: cycle 인덱스에 맞는 export_config.json, agent_result.txt를
# SCENARIO_DIR에 배치합니다.
#
# Arguments:
#   $1  yaml_file    — 시나리오 YAML 파일 경로
#   $2  cycle_index  — 배치할 cycle 인덱스 (0-based)
#   $3  scenario_dir — 파일을 배치할 디렉토리
#
# TODO: Activate when DLD-466 is implemented (remove the skip line below)
_level2_place_cycle_fixtures() {
  echo "[SKIP] _level2_place_cycle_fixtures: Not yet implemented (DLD-466)" && return 0

  local yaml_file="$1"
  local cycle_index="$2"
  local scenario_dir="$3"

  mkdir -p "$scenario_dir"

  # export_config 읽기 (null이면 파일 생성 안 함)
  local export_config_raw
  export_config_raw=$(yq eval ".cycles[${cycle_index}].export_config" "$yaml_file")

  if [[ "$export_config_raw" != "null" && -n "$export_config_raw" ]]; then
    # YAML 오브젝트를 JSON으로 변환하여 export_config.json에 저장
    yq eval -o=json ".cycles[${cycle_index}].export_config" "$yaml_file" \
      > "${scenario_dir}/export_config.json"
    log "Placed export_config.json for cycle ${cycle_index}"
  else
    log "No export_config for cycle ${cycle_index} — skipping export_config.json"
    rm -f "${scenario_dir}/export_config.json"
  fi

  # agent_result 읽기
  local agent_result
  agent_result=$(yq eval ".cycles[${cycle_index}].agent_result // \"\"" "$yaml_file")

  if [[ -n "$agent_result" && "$agent_result" != "null" ]]; then
    echo "$agent_result" > "${scenario_dir}/agent_result.txt"
    log "Placed agent_result.txt for cycle ${cycle_index}: $agent_result"
  else
    rm -f "${scenario_dir}/agent_result.txt"
  fi
}

# _level2_submit_mock_workflow: mock-agent를 사용하여 Argo Workflow를 제출합니다.
# SCENARIO_DIR ConfigMap을 생성하고 Workflow를 제출합니다.
#
# Arguments:
#   $1  scenario_name  — 시나리오 이름
#   $2  cycle_index    — cycle 인덱스
#   $3  max_depth      — 최대 depth (기본값: 5)
#   $4  scenario_dir   — fixture 파일 디렉토리
#
# 출력: workflow name
#
# TODO: Activate when DLD-466 is implemented (remove the skip line below)
_level2_submit_mock_workflow() {
  echo "[SKIP] _level2_submit_mock_workflow: Not yet implemented (DLD-466)" && return 0

  local scenario_name="$1"
  local cycle_index="$2"
  local max_depth="${3:-5}"
  local scenario_dir="$4"

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
      | kubectl apply -f - -n "$NAMESPACE" --context "$KUBE_CONTEXT"
  else
    # 빈 ConfigMap 생성 (depth-limit 시나리오처럼 export_config가 null인 경우)
    kubectl create configmap "$cm_name_safe" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" \
      --dry-run=client -o yaml \
      | kubectl apply -f - -n "$NAMESPACE" --context "$KUBE_CONTEXT"
  fi

  log "Submitting mock Argo Workflow (scenario=$scenario_name, cycle=$cycle_index, max_depth=$max_depth)"

  # Argo Workflow 제출 — mock-agent 이미지와 SCENARIO_DIR(ConfigMap 마운트)를 사용
  local submit_output
  submit_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="[mock] scenario=${scenario_name} cycle=${cycle_index}" \
    -p agent_image="$MOCK_AGENT_IMAGE" \
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
      --context "$KUBE_CONTEXT" || wait_exit=$?

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

# _level2_verify_cycle: 단일 cycle 검증 (assertions 필드 기반)
#
# Arguments:
#   $1  yaml_file      — 시나리오 YAML 파일 경로
#   $2  workflow_name  — 완료된 workflow 이름
#   $3  cycle_index    — 검증 중인 cycle 인덱스
#
# TODO: Activate when DLD-466 is implemented (remove the skip line below)
_level2_verify_cycle() {
  echo "[SKIP] _level2_verify_cycle: Not yet implemented (DLD-466)" && return 0

  local yaml_file="$1"
  local workflow_name="$2"
  local cycle_index="$3"

  log "Verifying cycle ${cycle_index} for workflow: $workflow_name"

  # 1. Workflow Succeeded 검증
  assert_workflow_succeeded "$workflow_name" "$NAMESPACE"

  # 2. router_decision 검증 (assertions.router_decisions 배열)
  local router_decision
  router_decision=$(yq eval ".assertions.router_decisions[${cycle_index}] // \"\"" "$yaml_file")
  if [[ -n "$router_decision" && "$router_decision" != "null" ]]; then
    log "Checking router_decision for cycle ${cycle_index}: expected='$router_decision'"
    # mock-api /assertions エンドポイント経由でルーター決定を確認
    assert_mock_api "query" "$router_decision"
  fi

  # assertions.router_decision (単数形、単一サイクル用)
  local single_router_decision
  single_router_decision=$(yq eval ".assertions.router_decision // \"\"" "$yaml_file")
  if [[ -n "$single_router_decision" && "$single_router_decision" != "null" ]]; then
    log "Checking router_decision: expected='$single_router_decision'"
    assert_mock_api "query" "$single_router_decision"
  fi

  # 3. linear_comment 검증
  local body_contains
  body_contains=$(yq eval ".assertions.linear_comment.body_contains // \"\"" "$yaml_file")
  if [[ -n "$body_contains" && "$body_contains" != "null" ]]; then
    log "Checking mock-api linear_comment body_contains: '$body_contains'"
    assert_mock_api "mutation" "$body_contains"
  fi

  # 4. github_pr 검증 (create_pr アクション)
  local github_pr_assertion
  github_pr_assertion=$(yq eval ".assertions.github_pr // false" "$yaml_file")
  if [[ "$github_pr_assertion" == "true" ]]; then
    log "Checking mock-api github_pr call"
    assert_mock_api "mutation" "create_pr"
  fi

  log "Cycle ${cycle_index} verification passed"
}

# run_scenario_level2: Level ② シナリオ実行 (mock-agent + mock-api)
# cycles[]を순회하며 mock-agent 방식으로 실행하고 검증합니다.
#
# Arguments:
#   $1  scenario_name  — 시나리오 이름
#
# TODO: Activate when DLD-466 is implemented (remove the skip line below)
run_scenario_level2() {
  echo "[SKIP] run_scenario_level2: Not yet implemented (DLD-466)" && return 0

  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== Level 2 Scenario: $scenario_name ==="

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

  # mock-api assertions 초기화
  local mock_api_base_url="${MOCK_API_URL:-http://localhost:4000}"
  curl -sf -X POST "${mock_api_base_url}/assertions/reset" > /dev/null 2>&1 || true
  log "Mock-api assertions reset (url=$mock_api_base_url)"

  # continue-then-stop 시나리오처럼 멀티 cycle인 경우:
  # 각 cycle을 독립적인 Workflow로 제출하고 검증합니다.
  local cycle_index
  local all_workflow_names=()

  for (( cycle_index=0; cycle_index<cycle_count; cycle_index++ )); do
    log "--- Cycle ${cycle_index}/${cycle_count} ---"

    # 임시 fixture 디렉토리 생성
    local cycle_dir
    cycle_dir=$(mktemp -d "/tmp/e2e-level2-${scenario_name}-cycle${cycle_index}-XXXXXX")

    # cycle fixtures 배치
    _level2_place_cycle_fixtures "$yaml_file" "$cycle_index" "$cycle_dir"

    # mock Argo Workflow 제출 + 완료 대기
    local workflow_name
    workflow_name=$(_level2_submit_mock_workflow \
      "$scenario_name" "$cycle_index" "$max_depth" "$cycle_dir")

    all_workflow_names+=("$workflow_name")

    # cycle 검증
    _level2_verify_cycle "$yaml_file" "$workflow_name" "$cycle_index"

    # 임시 디렉토리 정리
    rm -rf "$cycle_dir"
  done

  # --- シナリオレベルの追加検証 ---

  # continue-then-stop: run-cycle 재귀 2회 검증
  local scenario_name_check
  scenario_name_check=$(yaml_get "$yaml_file" '.name')
  if [[ "$scenario_name_check" == "continue-then-stop" ]]; then
    log "continue-then-stop: verifying run-cycle count across all workflows"
    # 複数サイクルを単一Workflowで実行する実装の場合、最後のworkflowで確認
    local last_workflow="${all_workflow_names[${#all_workflow_names[@]}-1]}"
    assert_run_cycle_count "$last_workflow" "$cycle_count" "$NAMESPACE"
  fi

  # depth-limit: max_depth 종료 검증
  if [[ "$scenario_name_check" == "depth-limit" ]]; then
    log "depth-limit: verifying max_depth termination"
    local last_workflow="${all_workflow_names[${#all_workflow_names[@]}-1]}"
    assert_max_depth_termination "$last_workflow" "$max_depth" "$NAMESPACE"
  fi

  # daemon pods ready 검증 (모든 workflow에 대해)
  for wf_name in "${all_workflow_names[@]}"; do
    assert_daemon_pods_ready "$wf_name" "$NAMESPACE"
    assert_work_dir_clean "$wf_name" "$NAMESPACE"
  done

  log "=== PASS (Level 2): $scenario_name ==="
}

# ═══════════════════════════════════════════════════════════════════════════════
# GENERIC SCENARIO RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

# discover_scenarios: 현재 LEVEL을 지원하는 시나리오 YAML 파일 목록을 반환합니다.
discover_scenarios() {
  local yaml_file
  for yaml_file in "$SCENARIOS_DIR"/*.yaml; do
    [[ -f "$yaml_file" ]] || continue
    # level 배열에 현재 LEVEL이 포함된 시나리오만 대상
    local has_level
    has_level=$(yq eval ".level[] | select(. == ${LEVEL})" "$yaml_file" 2>/dev/null || true)
    [[ -n "$has_level" ]] || continue
    yaml_get "$yaml_file" '.name'
  done
}

# run_scenario: YAML 정의를 읽고 setup → run → verify → teardown을 수행합니다.
# Level ②에서는 run_scenario_level2()로 위임합니다.
run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  # Level ② 분기 — mock-agent + mock-api 기반 실행
  # TODO: Activate when DLD-466 is implemented (remove the skip block below)
  if [[ "${LEVEL}" == "2" ]]; then
    run_scenario_level2 "$scenario_name"
    return 0
  fi

  log "=== Scenario: $scenario_name ==="

  # ── YAML에서 설정 읽기 ──
  local max_depth
  max_depth=$(yaml_get "$yaml_file" '.real.max_depth // 5')

  # setup/teardown/verify 목록 (YAML 배열 → 줄바꿈 구분 문자열)
  local setups teardowns verifies
  setups=$(yaml_get "$yaml_file" '.real.setup[]' 2>/dev/null || true)
  teardowns=$(yaml_get "$yaml_file" '.real.teardown[]' 2>/dev/null || true)
  verifies=$(yaml_get "$yaml_file" '.real.verify[]' 2>/dev/null || true)

  # ── Setup ──
  local linear_issue_id=""
  local github_branch=""

  local setup_item
  while IFS= read -r setup_item; do
    [[ -n "$setup_item" ]] || continue
    case "$setup_item" in
      linear_issue)
        linear_issue_id=$(setup_linear_test_issue "$scenario_name")
        ;;
      github_branch)
        github_branch=$(setup_github_test_branch "$scenario_name")
        ;;
      *) warn "Unknown setup type: $setup_item" ;;
    esac
  done <<< "$setups"

  # ── Teardown trap (cleanup even on failure) ──
  _teardown_handler() {
    local td_item
    while IFS= read -r td_item; do
      [[ -n "$td_item" ]] || continue
      case "$td_item" in
        linear_issue)  teardown_linear_issue "$linear_issue_id" ;;
        github_branch) teardown_github_pr_and_branch "$github_branch" ;;
        *) warn "Unknown teardown type: $td_item" ;;
      esac
    done <<< "$1"
  }
  # shellcheck disable=SC2064
  trap "_teardown_handler '$teardowns'" EXIT

  # ── Run ──
  local prompt
  prompt=$(build_prompt "$yaml_file" "$linear_issue_id" "$github_branch")
  run_argo_workflow "$scenario_name" "$prompt" "$max_depth"

  # ── Verify (assertions) ──
  local verify_item
  while IFS= read -r verify_item; do
    [[ -n "$verify_item" ]] || continue
    case "$verify_item" in
      linear_comment)
        local body_contains
        body_contains=$(yaml_get "$yaml_file" '.assertions.linear_comment.body_contains')
        verify_linear_comment "$linear_issue_id" "$body_contains"
        ;;
      github_pr)
        verify_github_pr "$github_branch"
        ;;
      *) warn "Unknown verify type: $verify_item" ;;
    esac
  done <<< "$verifies"

  # ── Teardown (explicit, then clear trap) ──
  _teardown_handler "$teardowns"
  trap - EXIT

  log "=== PASS: $scenario_name ==="
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log "Starting Level ${LEVEL} E2E test runner"
  log "SCENARIO=${SCENARIO}, LEVEL=${LEVEL}, NAMESPACE=${NAMESPACE}"

  check_prerequisites

  if [[ "$SCENARIO" == "all" ]]; then
    local scenarios
    scenarios=$(discover_scenarios)
    [[ -n "$scenarios" ]] \
      || die "No scenarios for level ${LEVEL} found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All scenarios completed"
}

main "$@"
