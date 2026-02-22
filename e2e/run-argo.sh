#!/usr/bin/env bash
# e2e/run-argo.sh — Level ③ E2E runner: kind + Argo + real Claude Agent + real APIs
#
# DLD-465: Level ③ 풀 e2e를 실제로 동작하게 구현.
#
# Usage:
#   ./e2e/run-argo.sh [--scenario <name|all>] [--level <2|3>] [--namespace <ns>]
#
# Environment variables (required):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포 (기본값: dlddu/pure-agent-e2e-sandbox)
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-3}"
NAMESPACE="${NAMESPACE:-pure-agent}"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-dlddu/pure-agent-e2e-sandbox}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds

# ── Source shared libraries ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
# shellcheck source=lib/setup-real.sh
source "$LIB_DIR/setup-real.sh" --source-only
# shellcheck source=lib/teardown-real.sh
source "$LIB_DIR/teardown-real.sh" --source-only

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

  [[ -n "${LINEAR_API_KEY:-}" ]]  || die "LINEAR_API_KEY is not set"
  [[ -n "${LINEAR_TEAM_ID:-}" ]]  || die "LINEAR_TEAM_ID is not set"
  [[ -n "${GITHUB_TOKEN:-}" ]]    || die "GITHUB_TOKEN is not set"

  log "Prerequisites OK"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# build_prompt: 시나리오별 프롬프트를 파일에서 읽고 변수를 치환합니다.
# 프롬프트 파일 위치: e2e/scenarios/<scenario_name>/prompt.txt
build_prompt() {
  local scenario_name="$1"
  local linear_issue_id="$2"
  local github_branch="${3:-}"

  local prompt_file="${SCRIPT_DIR}/scenarios/${scenario_name}/prompt.txt"
  [[ -f "$prompt_file" ]] \
    || die "Prompt file not found: $prompt_file"

  local prompt
  prompt=$(<"$prompt_file")

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
# VERIFY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# verify_linear_comment: Linear 이슈에 코멘트가 생성됐는지 검증합니다.
verify_linear_comment() {
  local linear_issue_id="$1"
  local expected_body_contains="${2:-}"

  log "Verifying Linear comment on issue: $linear_issue_id"

  local response
  response=$(curl -sf \
    -X POST \
    -H "Authorization: ${LINEAR_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg issueId "$linear_issue_id" \
      '{
        query: "query GetIssueComments($issueId: String!) { issue(id: $issueId) { comments { nodes { id body createdAt } } } }",
        variables: { issueId: $issueId }
      }')" \
    "https://api.linear.app/graphql")

  local comment_count
  comment_count=$(echo "$response" \
    | jq '.data.issue.comments.nodes | length')

  [[ "$comment_count" -gt 0 ]] \
    || die "FAIL verify_linear_comment: no comments found on issue $linear_issue_id"

  if [[ -n "$expected_body_contains" ]]; then
    local match_count
    match_count=$(echo "$response" \
      | jq --arg body "$expected_body_contains" \
        '[.data.issue.comments.nodes[] | select(.body | contains($body))] | length')
    [[ "$match_count" -gt 0 ]] \
      || die "FAIL verify_linear_comment: no comment containing '$expected_body_contains' found"
  fi

  log "PASS verify_linear_comment: $comment_count comment(s) found"
}

# verify_github_pr: GitHub PR이 생성됐는지 검증합니다 (create-pr-action 전용).
verify_github_pr() {
  local github_branch="$1"

  log "Verifying GitHub PR for branch: $github_branch (repo=$GITHUB_TEST_REPO)"

  local response
  response=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/pulls?head=${GITHUB_TEST_REPO%%/*}:${github_branch}&state=open")

  local pr_count
  pr_count=$(echo "$response" | jq 'length')

  [[ "$pr_count" -gt 0 ]] \
    || die "FAIL verify_github_pr: no open PR found for branch $github_branch"

  local pr_number
  pr_number=$(echo "$response" | jq -r '.[0].number')
  log "PASS verify_github_pr: PR #$pr_number found for branch $github_branch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCENARIO RUNNERS
# ═══════════════════════════════════════════════════════════════════════════════

# run_scenario_report_action: report-action 시나리오 실행
# Agent가 set_export_config(actions: ["report"])를 호출하고
# Export Handler가 Linear 코멘트를 작성하는지 검증합니다.
run_scenario_report_action() {
  local scenario_name="report-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id

  # Setup
  linear_issue_id=$(setup_linear_test_issue "$scenario_name")

  # Teardown trap (cleanup even on failure)
  trap "teardown_linear_issue '$linear_issue_id'" EXIT

  # Run
  local prompt
  prompt=$(build_prompt "$scenario_name" "$linear_issue_id")
  run_argo_workflow "$scenario_name" "$prompt" "5"

  # Verify
  verify_linear_comment "$linear_issue_id" "작업 완료"

  # Teardown
  teardown_linear_issue "$linear_issue_id"
  trap - EXIT

  log "=== PASS: $scenario_name ==="
}

# run_scenario_create_pr_action: create-pr-action 시나리오 실행
# Agent가 set_export_config(actions: ["create_pr"])를 호출하고
# GitHub PR 생성 + Linear 코멘트 작성을 검증합니다.
run_scenario_create_pr_action() {
  local scenario_name="create-pr-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id
  local github_branch

  # Setup
  linear_issue_id=$(setup_linear_test_issue "$scenario_name")
  github_branch=$(setup_github_test_branch "$scenario_name")

  # Teardown trap (cleanup even on failure)
  trap "teardown_linear_issue '$linear_issue_id'; teardown_github_pr_and_branch '$github_branch'" EXIT

  # Run
  local prompt
  prompt=$(build_prompt "$scenario_name" "$linear_issue_id" "$github_branch")
  run_argo_workflow "$scenario_name" "$prompt" "5"

  # Verify
  verify_linear_comment "$linear_issue_id" "PR"
  verify_github_pr "$github_branch"

  # Teardown
  teardown_github_pr_and_branch "$github_branch"
  teardown_linear_issue "$linear_issue_id"
  trap - EXIT

  log "=== PASS: $scenario_name ==="
}

# run_scenario_none_action: none-action 시나리오 실행
# Agent가 set_export_config(actions: ["none"])를 호출하고
# Export Handler가 Linear 코멘트를 작성하는지 검증합니다.
run_scenario_none_action() {
  local scenario_name="none-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id

  # Setup
  linear_issue_id=$(setup_linear_test_issue "$scenario_name")

  # Teardown trap (cleanup even on failure)
  trap "teardown_linear_issue '$linear_issue_id'" EXIT

  # Run
  local prompt
  prompt=$(build_prompt "$scenario_name" "$linear_issue_id")
  run_argo_workflow "$scenario_name" "$prompt" "5"

  # Verify
  verify_linear_comment "$linear_issue_id" "완료"

  # Teardown
  teardown_linear_issue "$linear_issue_id"
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

  case "$SCENARIO" in
    all)
      run_scenario_report_action
      run_scenario_create_pr_action
      run_scenario_none_action
      ;;
    report-action)       run_scenario_report_action ;;
    create-pr-action)    run_scenario_create_pr_action ;;
    none-action)         run_scenario_none_action ;;
    *)                   die "Unknown scenario: '$SCENARIO'. Valid values: all | report-action | create-pr-action | none-action" ;;
  esac

  log "All scenarios completed"
}

main "$@"
