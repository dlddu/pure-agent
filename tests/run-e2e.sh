#!/usr/bin/env bash
# tests/run-e2e.sh — E2E 테스트 러너 (kind + Argo, 실제 API)
#
# Mock:
#   - 없음 (모든 컴포넌트가 실제 서비스)
# Real:
#   - Agent        (실제 Claude Code 에이전트, Anthropic API 호출)
#   - Linear API   (이슈 생성 → 코멘트 검증 → 정리)
#   - GitHub API   (브랜치/PR 생성 → 검증 → 정리)
#   - Planner      (실제 Claude Haiku로 환경 선택)
#   - Gate         (실제 Python CLI)
#   - Export Handler (실제 TypeScript)
#   - Argo Workflows / Kubernetes
#   - MCP daemon / LLM gateway
#
# 시나리오 정의는 tests/scenarios/<name>.yaml 파일에서 읽습니다.
# YAML의 real.setup/teardown/max_depth 및 assertions 섹션을 사용하여
# 제네릭하게 시나리오를 실행합니다.
#
# Usage:
#   ./tests/run-e2e.sh [--scenario <name|all>] [--namespace <ns>] [--context <ctx>]
#
# Environment variables (required):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포
#
# Environment variables (optional):
#   SCENARIO              — 실행할 시나리오 이름 (기본값: all)
#   NAMESPACE             — Kubernetes 네임스페이스 (기본값: pure-agent)
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)
#   WORKFLOW_TIMEOUT      — Workflow 대기 타임아웃 초 (기본값: 600)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-e2e}"
NAMESPACE="${NAMESPACE:-pure-agent}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:?GITHUB_TEST_REPO is not set}"

# ── Source shared libraries ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/setup-real.sh
source "$LIB_DIR/setup-real.sh" --source-only
# shellcheck source=lib/teardown-real.sh
source "$LIB_DIR/teardown-real.sh" --source-only
# shellcheck source=lib/verify-real.sh
source "$LIB_DIR/verify-real.sh" --source-only
# shellcheck source=lib/assertions-argo.sh
source "$LIB_DIR/assertions-argo.sh" --source-only
# shellcheck source=lib/localstack.sh
source "$LIB_DIR/localstack.sh" --source-only

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[run-e2e] $*" >&2; }
warn() { echo "[run-e2e] WARN: $*" >&2; }
die()  { echo "[run-e2e] ERROR: $*" >&2; exit 1; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="$2";   shift 2 ;;
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --context)    KUBE_CONTEXT="$2"; shift 2 ;;
    *)            die "Unknown argument: $1" ;;
  esac
done

# ── Prerequisites check ─────────────────────────────────────────────────────
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
      --context "$KUBE_CONTEXT" >&2 || wait_exit=$?

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
# SCENARIO RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

# run_scenario: YAML 정의를 읽고 setup → run → verify → teardown을 수행합니다.
run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== E2E Scenario: $scenario_name ==="

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
  local linear_issue_identifier=""
  local github_branch=""

  local setup_item
  while IFS= read -r setup_item; do
    [[ -n "$setup_item" ]] || continue
    case "$setup_item" in
      linear_issue)
        local setup_output
        setup_output=$(setup_linear_test_issue "$scenario_name")
        linear_issue_id=$(echo "$setup_output" | sed -n '1p')
        linear_issue_identifier=$(echo "$setup_output" | sed -n '2p')
        log "Linear issue: id=$linear_issue_id identifier=$linear_issue_identifier"
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
  # Use identifier (e.g. DLD-123) in prompt so planner/agent can recognize it;
  # keep UUID (linear_issue_id) for teardown/verify API calls.
  local prompt_issue_ref="${linear_issue_identifier:-$linear_issue_id}"
  local prompt
  prompt=$(build_prompt "$yaml_file" "$prompt_issue_ref" "$github_branch")
  local workflow_name
  workflow_name=$(run_argo_workflow "$scenario_name" "$prompt" "$max_depth")

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
      planner_valid_image)
        assert_planner_valid_image "$workflow_name" "$NAMESPACE"
        ;;
      planner_exact_image)
        local expected_env_id
        expected_env_id=$(yaml_get "$yaml_file" '.assertions.planner_image')
        assert_planner_image "$workflow_name" "$expected_env_id" "$NAMESPACE"
        ;;
      s3_transcript)
        assert_s3_transcript_exists
        ;;
      *) warn "Unknown verify type: $verify_item" ;;
    esac
  done <<< "$verifies"

  # ── Teardown (explicit, then clear trap) ──
  _teardown_handler "$teardowns"
  trap - EXIT

  log "=== PASS (E2E): $scenario_name ==="
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log "Starting E2E test runner (kind + Argo, real API)"
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
      || die "No E2E scenarios found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All E2E scenarios completed"
}

main "$@"
