#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/verify-real.sh
#
# These tests define the expected behaviour of:
#   verify_linear_comment <issue_id> [body_contains]  -> checks comment exists; dies on failure
#   verify_github_pr <branch_name>                     -> checks open PR exists; dies on failure

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  export LINEAR_API_KEY="test-linear-key"
  export GITHUB_TOKEN="test-github-token"
  export GITHUB_TEST_REPO="testorg/testrepo"

  load_verify_real
}

# ── verify_linear_comment: happy path ─────────────────────────────────────────

@test "verify_linear_comment: exits 0 when comments exist" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"hello","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123"

  [ "$status" -eq 0 ]
}

@test "verify_linear_comment: exits 0 when body_contains matches" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"분석 리포트 완료","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123" "분석 리포트"

  [ "$status" -eq 0 ]
}

@test "verify_linear_comment: passes with multiple comments when one matches" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"unrelated","createdAt":"2025-01-01"},{"id":"c2","body":"작업 완료 report","createdAt":"2025-01-02"}]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123" "작업 완료"

  [ "$status" -eq 0 ]
}

# ── verify_linear_comment: assertion failures ─────────────────────────────────

@test "verify_linear_comment: fails when no comments exist" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123"

  [ "$status" -ne 0 ]
}

@test "verify_linear_comment: fails when body_contains does not match any comment" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"something else","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123" "분석 리포트"

  [ "$status" -ne 0 ]
}

@test "verify_linear_comment: error message mentions the missing substring" {
  curl() {
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"something else","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl

  run verify_linear_comment "issue-123" "분석 리포트"

  [ "$status" -ne 0 ]
  [[ "$output" == *"분석 리포트"* ]]
}

# ── verify_linear_comment: error cases ────────────────────────────────────────

@test "verify_linear_comment: fails when LINEAR_API_KEY is not set" {
  unset LINEAR_API_KEY

  run verify_linear_comment "issue-123"

  [ "$status" -ne 0 ]
}

@test "verify_linear_comment: fails when curl command fails" {
  curl() {
    return 1
  }
  export -f curl

  run verify_linear_comment "issue-123"

  [ "$status" -ne 0 ]
}

@test "verify_linear_comment: sends issue ID in the request" {
  local captured_args_file="$WORK_DIR/curl-args.txt"

  curl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"ok","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl
  export captured_args_file

  run verify_linear_comment "target-issue-id-789"

  [ "$status" -eq 0 ]
  grep -q "target-issue-id-789" "$captured_args_file"
}

@test "verify_linear_comment: calls the Linear API endpoint" {
  local captured_args_file="$WORK_DIR/curl-args.txt"

  curl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo '{"data":{"issue":{"comments":{"nodes":[{"id":"c1","body":"ok","createdAt":"2025-01-01"}]}}}}'
  }
  export -f curl
  export captured_args_file

  run verify_linear_comment "issue-123"

  [ "$status" -eq 0 ]
  grep -q "linear.app" "$captured_args_file"
}

# ── verify_github_pr: happy path ──────────────────────────────────────────────

@test "verify_github_pr: exits 0 when an open PR exists" {
  curl() {
    echo '[{"number":42,"state":"open"}]'
  }
  export -f curl

  run verify_github_pr "e2e-test/create-pr-action-20260101"

  [ "$status" -eq 0 ]
}

@test "verify_github_pr: output mentions the PR number" {
  curl() {
    echo '[{"number":42,"state":"open"}]'
  }
  export -f curl

  run verify_github_pr "e2e-test/create-pr-action-20260101"

  [ "$status" -eq 0 ]
  [[ "$output" == *"42"* ]]
}

# ── verify_github_pr: assertion failures ──────────────────────────────────────

@test "verify_github_pr: fails when no open PRs exist" {
  curl() {
    echo '[]'
  }
  export -f curl

  run verify_github_pr "e2e-test/create-pr-action-20260101"

  [ "$status" -ne 0 ]
}

@test "verify_github_pr: error message mentions the branch name" {
  curl() {
    echo '[]'
  }
  export -f curl

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -ne 0 ]
  [[ "$output" == *"e2e-test/some-branch"* ]]
}

# ── verify_github_pr: error cases ────────────────────────────────────────────

@test "verify_github_pr: fails when GITHUB_TOKEN is not set" {
  unset GITHUB_TOKEN

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -ne 0 ]
}

@test "verify_github_pr: fails when GITHUB_TEST_REPO is not set" {
  unset GITHUB_TEST_REPO

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -ne 0 ]
}

@test "verify_github_pr: fails when curl command fails" {
  curl() {
    return 1
  }
  export -f curl

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -ne 0 ]
}

@test "verify_github_pr: uses GITHUB_TOKEN for authorization" {
  local captured_args_file="$WORK_DIR/curl-args.txt"

  curl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo '[{"number":1}]'
  }
  export -f curl
  export captured_args_file

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  grep -q "test-github-token" "$captured_args_file"
}

@test "verify_github_pr: uses GITHUB_TEST_REPO in API URL" {
  local captured_args_file="$WORK_DIR/curl-args.txt"

  curl() {
    printf '%s\n' "$@" > "$captured_args_file"
    echo '[{"number":1}]'
  }
  export -f curl
  export captured_args_file

  run verify_github_pr "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  grep -q "testorg/testrepo" "$captured_args_file"
}
