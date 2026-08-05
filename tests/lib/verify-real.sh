#!/usr/bin/env bash
# tests/lib/verify-real.sh — E2E test verification helpers (real API calls)
#
# Functions:
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

# ── verify_s3_transcripts ────────────────────────────────────────────────────
# Verifies that transcripts exist in the LocalStack S3 bucket.
# Requires localstack.sh to be sourced and S3_ENDPOINT_URL to be set.
verify_s3_transcripts() {
  [[ -n "${S3_ENDPOINT_URL:-}" ]] || { warn "S3_ENDPOINT_URL not set, skipping S3 verification"; return 0; }

  log "Verifying S3 transcripts"
  assert_s3_transcript_exists
  log "PASS verify_s3_transcripts: transcripts found in S3"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi
