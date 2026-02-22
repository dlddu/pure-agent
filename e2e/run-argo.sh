#!/usr/bin/env bash
# e2e/run-argo.sh — Level ③ E2E runner: kind + Argo + real Claude Agent + real APIs
#
# DLD-464: 이 스크립트 전체가 SKIP 상태입니다.
#          skip 제거 후 실제 Linear / GitHub API로 실행 가능한 구조입니다.
#
# Usage:
#   ./e2e/run-argo.sh [--scenario <name|all>] [--namespace <ns>]
#
# Environment variables (required when not skipped):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포 (기본값: dlddu/pure-agent-e2e-sandbox)
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)
#
# Skip 제거 방법 (DLD-464 구현 완료 후):
#   1. 파일 상단의 SKIP_ALL 변수를 "false"로 변경
#   2. GitHub Actions secrets에 필요한 값을 등록
#   3. e2e-full.yaml workflow의 E2E_SKIP env를 "false"로 변경

set -euo pipefail

# ── SKIP 플래그 ──────────────────────────────────────────────────────────────
# TODO(DLD-464): 구현 완료 후 SKIP_ALL="false" 로 변경
SKIP_ALL="${SKIP_ALL:-true}"

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
NAMESPACE="${NAMESPACE:-pure-agent}"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-dlddu/pure-agent-e2e-sandbox}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-300}"  # seconds

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[run-argo] $*" >&2; }
warn() { echo "[run-argo] WARN: $*" >&2; }
die()  { echo "[run-argo] ERROR: $*" >&2; exit 1; }

# ── Skip helper ──────────────────────────────────────────────────────────────
# DLD-464: SKIP_ALL=true 인 경우 각 함수 시작 시 이 함수를 호출하여 skip합니다.
# skip 제거 시 이 함수 호출 줄들을 삭제하세요.
skip_if_disabled() {
  local reason="${1:-Pending implementation: DLD-464}"
  if [[ "$SKIP_ALL" == "true" ]]; then
    log "SKIP: $reason"
    return 0
  fi
  return 1
}

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="$2";   shift 2 ;;
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --context)    KUBE_CONTEXT="$2"; shift 2 ;;
    *)            die "Unknown argument: $1" ;;
  esac
done

# ── Prerequisites check ──────────────────────────────────────────────────────
check_prerequisites() {
  # SKIP(DLD-464): prerequisites 확인 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "check_prerequisites: Pending implementation: DLD-464"; then return 0; fi

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
# SETUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# setup_linear_issue: Linear에 테스트 이슈를 생성하고 이슈 ID를 출력합니다.
# 출력: Linear issue ID (예: "ABC-123")
setup_linear_issue() {
  local scenario_name="$1"
  local issue_title="[E2E-TEST] ${scenario_name} — $(date '+%Y-%m-%dT%H:%M:%S')"

  # SKIP(DLD-464): Linear 이슈 생성 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "setup_linear_issue: Pending implementation: DLD-464"; then
    echo "SKIP-ISSUE-ID"
    return 0
  fi

  log "Creating Linear test issue: $issue_title"

  local response
  response=$(curl -sf \
    -X POST \
    -H "Authorization: ${LINEAR_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg title "$issue_title" \
      --arg teamId "$LINEAR_TEAM_ID" \
      '{
        query: "mutation CreateIssue($title: String!, $teamId: String!) { issueCreate(input: { title: $title, teamId: $teamId }) { success issue { id identifier } } }",
        variables: { title: $title, teamId: $teamId }
      }')" \
    "https://api.linear.app/graphql")

  local issue_id
  issue_id=$(echo "$response" | jq -r '.data.issueCreate.issue.id')
  local issue_identifier
  issue_identifier=$(echo "$response" | jq -r '.data.issueCreate.issue.identifier')

  [[ "$issue_id" != "null" && -n "$issue_id" ]] \
    || die "Failed to create Linear issue. Response: $response"

  log "Created Linear issue: $issue_identifier (id=$issue_id)"
  echo "$issue_id"
}

# setup_github_branch: GitHub 테스트 레포에 E2E 테스트용 브랜치를 초기화합니다.
# 출력: 브랜치명
setup_github_branch() {
  local scenario_name="$1"
  local branch="${GITHUB_TEST_BRANCH_PREFIX}/${scenario_name}-$(date '+%Y%m%d%H%M%S')"

  # SKIP(DLD-464): GitHub 브랜치 초기화 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "setup_github_branch: Pending implementation: DLD-464"; then
    echo "SKIP-BRANCH"
    return 0
  fi

  log "Initializing GitHub test branch: $branch (repo=$GITHUB_TEST_REPO)"

  # 기본 브랜치(main)의 최신 SHA를 가져옵니다
  local base_sha
  base_sha=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/git/ref/heads/main" \
    | jq -r '.object.sha')

  [[ "$base_sha" != "null" && -n "$base_sha" ]] \
    || die "Failed to get base SHA from GitHub. Repo: $GITHUB_TEST_REPO"

  # 새 브랜치 생성
  curl -sf \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/git/refs" \
    -d "$(jq -n --arg ref "refs/heads/$branch" --arg sha "$base_sha" \
      '{ref: $ref, sha: $sha}')" \
    > /dev/null

  log "Created GitHub branch: $branch"
  echo "$branch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# build_prompt: 시나리오별 실제 API 프롬프트를 생성합니다.
build_prompt() {
  local scenario_name="$1"
  local linear_issue_id="$2"
  local github_branch="${3:-}"

  case "$scenario_name" in
    report-action)
      echo "Linear 이슈 ${linear_issue_id}를 읽고 내용을 요약해서 report로 작성해주세요."
      ;;
    create-pr-action)
      echo "테스트 레포 ${GITHUB_TEST_REPO}에 hello.txt 파일을 생성하고 PR을 만들어주세요. 브랜치명은 ${github_branch} 를 사용하세요."
      ;;
    none-action)
      echo "Linear 이슈 ${linear_issue_id}에 '완료'라고 코멘트만 남기고 종료해주세요."
      ;;
    *)
      die "Unknown scenario: $scenario_name"
      ;;
  esac
}

# run_argo_workflow: Argo Workflow를 제출하고 완료까지 대기합니다.
# 출력: workflow name (예: "pure-agent-abcde")
run_argo_workflow() {
  local scenario_name="$1"
  local prompt="$2"
  local max_depth="${3:-5}"

  # SKIP(DLD-464): Argo Workflow 실행 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "run_argo_workflow: Pending implementation: DLD-464"; then
    echo "SKIP-WORKFLOW-NAME"
    return 0
  fi

  log "Submitting Argo Workflow for scenario: $scenario_name"
  log "Prompt: $prompt"

  local workflow_output
  workflow_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="$prompt" \
    --wait \
    --timeout "${WORKFLOW_TIMEOUT}s" \
    --output json 2>&1) || {
      warn "Argo workflow submission failed:"
      echo "$workflow_output" >&2
      die "Workflow failed for scenario: $scenario_name"
    }

  local workflow_name
  workflow_name=$(echo "$workflow_output" | jq -r '.metadata.name')
  local workflow_phase
  workflow_phase=$(echo "$workflow_output" | jq -r '.status.phase')

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

  # SKIP(DLD-464): Linear 코멘트 검증 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "verify_linear_comment: Pending implementation: DLD-464"; then return 0; fi

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

  # SKIP(DLD-464): GitHub PR 검증 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "verify_github_pr: Pending implementation: DLD-464"; then return 0; fi

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
# TEARDOWN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# teardown_linear_issue: 테스트 이슈를 archive합니다.
teardown_linear_issue() {
  local linear_issue_id="$1"

  # SKIP(DLD-464): Linear 이슈 teardown — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "teardown_linear_issue: Pending implementation: DLD-464"; then return 0; fi

  log "Archiving Linear test issue: $linear_issue_id"

  local response
  response=$(curl -sf \
    -X POST \
    -H "Authorization: ${LINEAR_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg issueId "$linear_issue_id" \
      '{
        query: "mutation ArchiveIssue($issueId: String!) { issueArchive(id: $issueId) { success } }",
        variables: { issueId: $issueId }
      }')" \
    "https://api.linear.app/graphql")

  local success
  success=$(echo "$response" | jq -r '.data.issueArchive.success')
  [[ "$success" == "true" ]] \
    || warn "Failed to archive Linear issue $linear_issue_id (may need manual cleanup)"

  log "Archived Linear issue: $linear_issue_id"
}

# teardown_github_pr_and_branch: PR을 close하고 브랜치를 삭제합니다 (create-pr-action 전용).
teardown_github_pr_and_branch() {
  local github_branch="$1"

  # SKIP(DLD-464): GitHub PR/브랜치 teardown — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "teardown_github_pr_and_branch: Pending implementation: DLD-464"; then return 0; fi

  log "Closing GitHub PRs and deleting branch: $github_branch"

  # 해당 브랜치의 열린 PR을 모두 close합니다
  local prs
  prs=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/pulls?head=${GITHUB_TEST_REPO%%/*}:${github_branch}&state=open" \
    | jq -r '.[].number')

  for pr_number in $prs; do
    curl -sf \
      -X PATCH \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_TEST_REPO}/pulls/${pr_number}" \
      -d '{"state":"closed"}' \
      > /dev/null
    log "Closed PR #$pr_number"
  done

  # 브랜치 삭제
  curl -sf \
    -X DELETE \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/git/refs/heads/${github_branch}" \
    > /dev/null || warn "Failed to delete branch $github_branch (may not exist)"

  log "Deleted branch: $github_branch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCENARIO RUNNERS
# ═══════════════════════════════════════════════════════════════════════════════

# run_scenario_report_action: report-action 시나리오 실행
# Agent가 set_export_config(actions: ["report"])를 호출하고
# Export Handler가 Linear 코멘트를 작성하는지 검증합니다.
run_scenario_report_action() {
  # SKIP(DLD-464): report-action 시나리오 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "run_scenario_report_action: Pending implementation: DLD-464"; then
    log "[SKIP] report-action scenario skipped (DLD-464)"
    return 0
  fi

  local scenario_name="report-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id
  local github_branch="SKIP-BRANCH"

  # Setup
  linear_issue_id=$(setup_linear_issue "$scenario_name")

  # Teardown trap (cleanup even on failure)
  trap "teardown_linear_issue '$linear_issue_id'" EXIT

  # Run
  local prompt
  prompt=$(build_prompt "$scenario_name" "$linear_issue_id" "$github_branch")
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
  # SKIP(DLD-464): create-pr-action 시나리오 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "run_scenario_create_pr_action: Pending implementation: DLD-464"; then
    log "[SKIP] create-pr-action scenario skipped (DLD-464)"
    return 0
  fi

  local scenario_name="create-pr-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id
  local github_branch

  # Setup
  linear_issue_id=$(setup_linear_issue "$scenario_name")
  github_branch=$(setup_github_branch "$scenario_name")

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
  # SKIP(DLD-464): none-action 시나리오 — skip 제거 시 이 블록을 삭제하세요
  if skip_if_disabled "run_scenario_none_action: Pending implementation: DLD-464"; then
    log "[SKIP] none-action scenario skipped (DLD-464)"
    return 0
  fi

  local scenario_name="none-action"
  log "=== Scenario: $scenario_name ==="

  local linear_issue_id
  local github_branch="SKIP-BRANCH"

  # Setup
  linear_issue_id=$(setup_linear_issue "$scenario_name")

  # Teardown trap (cleanup even on failure)
  trap "teardown_linear_issue '$linear_issue_id'" EXIT

  # Run
  local prompt
  prompt=$(build_prompt "$scenario_name" "$linear_issue_id" "$github_branch")
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
  log "Starting Level ③ E2E test runner"
  log "SKIP_ALL=${SKIP_ALL}, SCENARIO=${SCENARIO}, NAMESPACE=${NAMESPACE}"

  if [[ "$SKIP_ALL" == "true" ]]; then
    log "==========================================================="
    log "SKIP: 모든 시나리오가 skip 상태입니다 (DLD-464)"
    log "      구현 완료 후 SKIP_ALL=false 로 변경하세요"
    log "==========================================================="
  fi

  check_prerequisites

  # SKIP_ALL=true 인 경우 시나리오 케이스에 진입하지 않고 아래에서 직접 실행합니다.
  # skip 함수 내부에서 이미 return 0이 처리되므로 die()가 호출되지 않도록 합니다.
  if [[ "$SKIP_ALL" == "true" ]]; then
    run_scenario_report_action
    run_scenario_create_pr_action
    run_scenario_none_action
  else
    case "$SCENARIO" in
      all)
        run_scenario_report_action
        run_scenario_create_pr_action
        run_scenario_none_action
        ;;
      report-action)
        run_scenario_report_action
        ;;
      create-pr-action)
        run_scenario_create_pr_action
        ;;
      none-action)
        run_scenario_none_action
        ;;
      *)
        die "Unknown scenario: '$SCENARIO'. Valid values: all | report-action | create-pr-action | none-action"
        ;;
    esac
  fi

  log "All scenarios completed (SKIP_ALL=${SKIP_ALL})"
}

# Source guard
if [[ "${1:-}" == "--source-only" ]]; then
  true
else
  main "$@"
fi
