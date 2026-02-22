#!/usr/bin/env bash
# e2e/lib/setup-real.sh — E2E test setup helpers (real API calls)
#
# Functions:
#   setup_linear_test_issue <scenario_name>  -> prints Linear issue ID to stdout
#   setup_github_test_branch <scenario_name> -> prints branch name to stdout
#
# Usage (source-only):
#   source "$LIB_DIR/setup-real.sh" --source-only

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-dlddu/pure-agent-e2e-sandbox}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[setup-real] $*" >&2; }
warn() { echo "[setup-real] WARN: $*" >&2; }
die()  { echo "[setup-real] ERROR: $*" >&2; exit 1; }

# ── setup_linear_test_issue ──────────────────────────────────────────────────
# Creates a Linear test issue and prints the issue ID to stdout.
# Args:
#   $1  scenario_name
setup_linear_test_issue() {
  local scenario_name="$1"

  [[ -n "${LINEAR_API_KEY:-}" ]] || die "LINEAR_API_KEY is not set"
  [[ -n "${LINEAR_TEAM_ID:-}" ]] || die "LINEAR_TEAM_ID is not set"

  local issue_title
  issue_title="[E2E-TEST] ${scenario_name} — $(date '+%Y-%m-%dT%H:%M:%S')"
  log "Creating Linear test issue: $issue_title"

  local query
  # shellcheck disable=SC2016
  query=$(printf '{"query":"mutation CreateIssue($title: String!, $teamId: String!) { issueCreate(input: { title: $title, teamId: $teamId }) { success issue { id identifier } } }","variables":{"title":"%s","teamId":"%s"}}' \
    "$issue_title" "$LINEAR_TEAM_ID")

  local response
  response=$(curl -sf \
    -X POST \
    -H "Authorization: ${LINEAR_API_KEY}" \
    -H "Content-Type: application/json" \
    --data "$query" \
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

# ── setup_github_test_branch ─────────────────────────────────────────────────
# Creates a GitHub branch for E2E testing and prints the branch name to stdout.
# Args:
#   $1  scenario_name
setup_github_test_branch() {
  local scenario_name="$1"

  [[ -n "${GITHUB_TOKEN:-}" ]]    || die "GITHUB_TOKEN is not set"
  [[ -n "${GITHUB_TEST_REPO:-}" ]] || die "GITHUB_TEST_REPO is not set"

  local branch
  branch="${GITHUB_TEST_BRANCH_PREFIX}/${scenario_name}-$(date '+%Y%m%d%H%M%S')"
  log "Initializing GitHub test branch: $branch (repo=$GITHUB_TEST_REPO)"

  # Get the latest SHA of the base branch (main)
  local base_sha
  base_sha=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/git/ref/heads/main" \
    | jq -r '.object.sha')

  [[ "$base_sha" != "null" && -n "$base_sha" ]] \
    || die "Failed to get base SHA from GitHub. Repo: $GITHUB_TEST_REPO"

  # Create the new branch — use || die so failure is detected even inside
  # command-substitution subshells where set -e is suppressed by POSIX.
  curl -sf \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_TEST_REPO}/git/refs" \
    -d "$(printf '{"ref":"refs/heads/%s","sha":"%s"}' "$branch" "$base_sha")" \
    > /dev/null \
    || die "Failed to create GitHub branch: $branch"

  log "Created GitHub branch: $branch"
  echo "$branch"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi
