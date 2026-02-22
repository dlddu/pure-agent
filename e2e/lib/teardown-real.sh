#!/usr/bin/env bash
# e2e/lib/teardown-real.sh — E2E test teardown helpers (real API calls)
#
# Functions:
#   teardown_linear_issue <issue_id>            -> archives the issue; warns on failure
#   teardown_github_pr_and_branch <branch_name> -> closes PRs + deletes branch; warns on failure
#
# Contract: these functions NEVER exit non-zero. All failures are warn-only.
#
# Usage (source-only):
#   source "$LIB_DIR/teardown-real.sh" --source-only

# Intentionally no set -euo pipefail: teardown must not propagate errors.

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[teardown-real] $*" >&2; }
warn() { echo "[teardown-real] WARN: $*" >&2; }

# ── teardown_linear_issue ────────────────────────────────────────────────────
# Archives a Linear issue. Warns on any failure; always exits 0.
# Args:
#   $1  issue_id
teardown_linear_issue() {
  local issue_id="$1"
  log "Archiving Linear test issue: $issue_id"

  local query
  query=$(printf '{"query":"mutation ArchiveIssue($issueId: String!) { issueArchive(id: $issueId) { success } }","variables":{"issueId":"%s"}}' \
    "$issue_id")

  local response
  if ! response=$(curl -sf \
    -X POST \
    -H "Authorization: ${LINEAR_API_KEY:-}" \
    -H "Content-Type: application/json" \
    --data "$query" \
    "https://api.linear.app/graphql"); then
    warn "curl failed while archiving Linear issue $issue_id"
    return 0
  fi

  local success
  success=$(echo "$response" | jq -r '.data.issueArchive.success' 2>/dev/null) || success=""

  if [[ "$success" != "true" ]]; then
    warn "Failed to archive Linear issue $issue_id (may need manual cleanup). Response: $response"
    return 0
  fi

  log "Archived Linear issue: $issue_id"
  return 0
}

# ── teardown_github_pr_and_branch ────────────────────────────────────────────
# Closes all open PRs for the branch and then deletes the branch.
# Warns on any failure; always exits 0.
# Args:
#   $1  branch_name
teardown_github_pr_and_branch() {
  local github_branch="$1"
  local repo="${GITHUB_TEST_REPO:-}"
  local repo_owner="${repo%%/*}"
  log "Closing GitHub PRs and deleting branch: $github_branch"

  # List open PRs for the branch
  local prs_json
  if ! prs_json=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN:-}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/pulls?head=${repo_owner}:${github_branch}&state=open"); then
    warn "curl failed while listing PRs for branch $github_branch"
    prs_json="[]"
  fi

  # Parse PR numbers; fall back gracefully on bad JSON
  local pr_numbers
  pr_numbers=$(echo "$prs_json" | jq -r '.[].number' 2>/dev/null) || pr_numbers=""

  for pr_number in $pr_numbers; do
    if ! curl -sf \
      -X PATCH \
      -H "Authorization: token ${GITHUB_TOKEN:-}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repo}/pulls/${pr_number}" \
      -d '{"state":"closed"}' \
      > /dev/null; then
      warn "curl failed while closing PR #$pr_number for branch $github_branch"
    else
      log "Closed PR #$pr_number"
    fi
  done

  # Delete the branch
  if ! curl -sf \
    -X DELETE \
    -H "Authorization: token ${GITHUB_TOKEN:-}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/git/refs/heads/${github_branch}" \
    > /dev/null; then
    warn "Failed to delete branch $github_branch (may not exist or curl failed)"
    return 0
  fi

  log "Deleted branch: $github_branch"
  return 0
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi
