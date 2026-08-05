#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for tests/lib/teardown-real.sh
#
# TDD Red Phase: teardown-real.sh does not yet exist.
# These tests define the expected behaviour of:
#   teardown_github_pr_and_branch <branch_name>    -> closes PRs + deletes branch; warns on failure

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  # Provide required env vars.
  export GITHUB_TOKEN="test-github-token"
  export GITHUB_TEST_REPO="testorg/testrepo"

  load_teardown_real
}

# ── teardown_github_pr_and_branch: happy path ─────────────────────────────────

@test "teardown_github_pr_and_branch: exits with code 0 on success" {
  # Arrange — first curl lists PRs (one PR found), second closes it, third deletes branch
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1) echo '[{"number":7}]' ;;   # list open PRs
      2) echo '{"number":7,"state":"closed"}' ;;  # close PR
      3) echo '' ;;                  # delete branch (204 no body)
    esac
  }
  export -f curl
  export call_file

  # Act
  run teardown_github_pr_and_branch "e2e-test/create-pr-action-20260101"

  # Assert
  [ "$status" -eq 0 ]
}

@test "teardown_github_pr_and_branch: exits with code 0 when no open PRs exist" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1) echo '[]' ;;   # no open PRs
      2) echo '' ;;      # delete branch
    esac
  }
  export -f curl
  export call_file

  run teardown_github_pr_and_branch "e2e-test/create-pr-action-20260101"

  [ "$status" -eq 0 ]
}

@test "teardown_github_pr_and_branch: closes all open PRs for the branch" {
  # Arrange — two open PRs exist
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  local close_calls_file="$WORK_DIR/close-calls.txt"
  touch "$close_calls_file"

  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1)
        # List PRs — return two PR numbers
        echo '[{"number":10},{"number":11}]'
        ;;
      2|3)
        # Close PRs
        echo "close" >> "$close_calls_file"
        echo '{"state":"closed"}'
        ;;
      4)
        # Delete branch
        echo ''
        ;;
    esac
  }
  export -f curl
  export call_file
  export close_calls_file

  run teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  local count
  count=$(wc -l < "$close_calls_file")
  [ "$count" -eq 2 ]
}

@test "teardown_github_pr_and_branch: deletes the branch after closing PRs" {
  local captured_args_file="$WORK_DIR/curl-args.txt"
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"

  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    # Append each invocation's args to the captured file
    printf 'CALL %s: %s\n' "$n" "$*" >> "$captured_args_file"
    case "$n" in
      1) echo '[]' ;;
      2) echo '' ;;
    esac
  }
  export -f curl
  export call_file
  export captured_args_file

  run teardown_github_pr_and_branch "e2e-test/feature-branch"

  [ "$status" -eq 0 ]
  # The DELETE call for the branch must appear
  grep -qi "DELETE\|delete\|refs/heads" "$captured_args_file"
}

# ── teardown_github_pr_and_branch: error / warn-only behaviour ────────────────

@test "teardown_github_pr_and_branch: does NOT exit non-zero when branch deletion fails" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1) echo '[]' ;;  # no open PRs
      2) return 1 ;;   # DELETE branch -> network error
    esac
  }
  export -f curl
  export call_file

  # Act
  run teardown_github_pr_and_branch "e2e-test/some-branch"

  # Assert — warn-only, not die
  [ "$status" -eq 0 ]
}

@test "teardown_github_pr_and_branch: outputs a warning when branch deletion fails" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1) echo '[]' ;;
      2) return 1 ;;
    esac
  }
  export -f curl
  export call_file

  run --separate-stderr teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warn"* ]] || [[ "$stderr" == *"WARN"* ]] || [[ "$stderr" == *"Warning"* ]] || [[ "$stderr" == *"fail"* ]] || [[ "$stderr" == *"Failed"* ]]
}

@test "teardown_github_pr_and_branch: does NOT exit non-zero when PR close fails" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    case "$n" in
      1) echo '[{"number":5}]' ;;  # one PR
      2) return 1 ;;               # close PR fails
      3) echo '' ;;                # delete branch succeeds
    esac
  }
  export -f curl
  export call_file

  run teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
}

@test "teardown_github_pr_and_branch: does NOT exit non-zero when list PRs curl fails" {
  curl() {
    return 1
  }
  export -f curl

  run teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
}

@test "teardown_github_pr_and_branch: uses GITHUB_TOKEN for authorization" {
  local captured_args_file="$WORK_DIR/curl-args.txt"
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"

  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    printf '%s\n' "$@" >> "$captured_args_file"
    case "$n" in
      1) echo '[]' ;;
      2) echo '' ;;
    esac
  }
  export -f curl
  export call_file
  export captured_args_file

  run teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  grep -q "test-github-token" "$captured_args_file"
}

@test "teardown_github_pr_and_branch: uses GITHUB_TEST_REPO in API URLs" {
  local captured_args_file="$WORK_DIR/curl-args.txt"
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"

  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    printf '%s\n' "$@" >> "$captured_args_file"
    case "$n" in
      1) echo '[]' ;;
      2) echo '' ;;
    esac
  }
  export -f curl
  export call_file
  export captured_args_file

  run teardown_github_pr_and_branch "e2e-test/some-branch"

  [ "$status" -eq 0 ]
  grep -q "testorg/testrepo" "$captured_args_file"
}
