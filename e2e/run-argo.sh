#!/usr/bin/env bash
# e2e/run-argo.sh — Level ③ E2E runner: kind + Argo + real Claude Agent + real APIs
#
# DLD-465: Level ③ 풀 e2e를 실제로 동작하게 구현.
#
# 시나리오 정의는 e2e/scenarios/<name>.yaml 파일에서 읽습니다.
# YAML의 real.setup/teardown/max_depth 및 assertions 섹션을 사용하여
# 제네릭하게 시나리오를 실행합니다.
#
# Usage:
#   ./e2e/run-argo.sh [--scenario <name|all>] [--level <2|3>] [--namespace <ns>]
#
# Environment variables (required):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-3}"
NAMESPACE="${NAMESPACE:-pure-agent}"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:?GITHUB_TEST_REPO is not set}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds

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

# ── Prerequisites check ──────────────────────────────────────────────────────
check_prerequisites() {
  command -v argo    >/dev/null 2>&1 || die "argo CLI is not installed"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"
  command -v curl    >/dev/null 2>&1 || die "curl is not installed"
  command -v jq      >/dev/null 2>&1 || die "jq is not installed"
  command -v yq      >/dev/null 2>&1 || die "yq is not installed"

  [[ -n "${LINEAR_API_KEY:-}" ]]  || die "LINEAR_API_KEY is not set"
  [[ -n "${LINEAR_TEAM_ID:-}" ]]  || die "LINEAR_TEAM_ID is not set"
  [[ -n "${GITHUB_TOKEN:-}" ]]    || die "GITHUB_TOKEN is not set"

  log "Prerequisites OK"
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
run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

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
