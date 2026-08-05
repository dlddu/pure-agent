#!/usr/bin/env bash
# tests/lib/setup-real.sh — E2E test setup helpers (real API calls)
#
# Functions:
#   setup_github_test_branch <scenario_name> -> prints branch name to stdout
#
# Usage (source-only):
#   source "$LIB_DIR/setup-real.sh" --source-only

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-}"
GITHUB_TEST_BRANCH_PREFIX="e2e-test"

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[setup-real] $*" >&2; }
warn() { echo "[setup-real] WARN: $*" >&2; }
die()  { echo "[setup-real] ERROR: $*" >&2; exit 1; }

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
    -d "$(jq -n --arg ref "refs/heads/$branch" --arg sha "$base_sha" \
      '{ref: $ref, sha: $sha}')" \
    > /dev/null \
    || die "Failed to create GitHub branch: $branch"

  log "Created GitHub branch: $branch"
  echo "$branch"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi
