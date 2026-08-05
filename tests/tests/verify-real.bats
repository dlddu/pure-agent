#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for tests/lib/verify-real.sh
#
# These tests define the expected behaviour of:
#   verify_github_pr <branch_name>                     -> checks open PR exists; dies on failure

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  export GITHUB_TOKEN="test-github-token"
  export GITHUB_TEST_REPO="testorg/testrepo"

  load_verify_real
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
