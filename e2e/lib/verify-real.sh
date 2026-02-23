#!/usr/bin/env bash
# e2e/lib/verify-real.sh — E2E test verification helpers (real API calls)
#
# Functions:
#   verify_linear_comment <issue_id> [body_contains]  -> checks comment exists
#   verify_github_pr <branch_name>                     -> checks open PR exists
#
# Contract: these functions die on assertion failure.
#
# Usage (source-only):
#   source "$LIB_DIR/verify-real.sh" --source-only

set -euo pipefail

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[verify-real] $*" >&2; }
warn() { echo "[verify-real] WARN: $*" >&2; }
die()  { echo "[verify-real] ERROR: $*" >&2; exit 1; }

# ── verify_linear_comment ────────────────────────────────────────────────────
# Verifies that at least one comment exists on a Linear issue.
# Optionally checks that a comment body contains a given substring.
# Args:
#   $1  linear_issue_id
#   $2  expected_body_contains (optional)
verify_linear_comment() {
  local linear_issue_id="$1"
  local expected_body_contains="${2:-}"

  [[ -n "${LINEAR_API_KEY:-}" ]] || die "LINEAR_API_KEY is not set"

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
    "https://api.linear.app/graphql") \
    || die "FAIL verify_linear_comment: curl failed for issue $linear_issue_id"

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

# ── verify_github_pr ─────────────────────────────────────────────────────────
# Verifies that at least one open PR exists for the given branch.
# Args:
#   $1  github_branch
verify_github_pr() {
  local github_branch="$1"
  local repo="${GITHUB_TEST_REPO:-}"

  [[ -n "${GITHUB_TOKEN:-}" ]]  || die "GITHUB_TOKEN is not set"
  [[ -n "$repo" ]]              || die "GITHUB_TEST_REPO is not set"

  log "Verifying GitHub PR for branch: $github_branch (repo=$repo)"

  local response
  response=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/pulls?head=${repo%%/*}:${github_branch}&state=open") \
    || die "FAIL verify_github_pr: curl failed for branch $github_branch"

  local pr_count
  pr_count=$(echo "$response" | jq 'length')

  [[ "$pr_count" -gt 0 ]] \
    || die "FAIL verify_github_pr: no open PR found for branch $github_branch"

  local pr_number
  pr_number=$(echo "$response" | jq -r '.[0].number')
  log "PASS verify_github_pr: PR #$pr_number found for branch $github_branch"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi
