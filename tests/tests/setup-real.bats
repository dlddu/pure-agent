#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for tests/lib/setup-real.sh
#
# TDD Red Phase: setup-real.sh does not yet exist.
# These tests define the expected behaviour of:
#   setup_github_test_branch <scenario_name> -> prints branch name

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  # Provide required env vars so the sourced script does not die immediately.
  export GITHUB_TOKEN="test-github-token"
  export GITHUB_TEST_REPO="testorg/testrepo"

  load_setup_real
}

# ── setup_github_test_branch: happy path ──────────────────────────────────────

@test "setup_github_test_branch: returns a non-empty branch name on success" {
  # Arrange — first curl call returns base SHA, second creates the branch
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    if [ "$n" -eq 1 ]; then
      # GET /git/ref/heads/main -> base SHA
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      # POST /git/refs -> branch created (empty body on success)
      echo '{}'
    fi
  }
  export -f curl
  export call_file

  # Act
  run setup_github_test_branch "create-pr-action"

  # Assert
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "setup_github_test_branch: branch name contains the scenario name" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    if [ "$n" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      echo '{}'
    fi
  }
  export -f curl
  export call_file

  run setup_github_test_branch "create-pr-action"

  [ "$status" -eq 0 ]
  [[ "$output" == *"create-pr-action"* ]]
}

@test "setup_github_test_branch: branch name contains the e2e-test prefix" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    if [ "$n" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      echo '{}'
    fi
  }
  export -f curl
  export call_file

  run setup_github_test_branch "some-scenario"

  [ "$status" -eq 0 ]
  [[ "$output" == *"e2e-test"* ]]
}

# ── setup_github_test_branch: error cases ─────────────────────────────────────

@test "setup_github_test_branch: fails when GITHUB_TOKEN is not set" {
  unset GITHUB_TOKEN

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: fails when GITHUB_TEST_REPO is not set" {
  unset GITHUB_TEST_REPO

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: fails when base SHA is null" {
  curl() {
    echo '{"object":{"sha":"null"}}'
  }
  export -f curl

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: fails when first curl call (get SHA) fails" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    if [ "$n" -eq 1 ]; then
      return 1
    fi
    echo '{}'
  }
  export -f curl
  export call_file

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: fails when branch creation curl call fails" {
  local call_file="$WORK_DIR/curl-calls.txt"
  echo "0" > "$call_file"
  curl() {
    local n
    n=$(cat "$call_file")
    n=$((n + 1))
    echo "$n" > "$call_file"
    if [ "$n" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      return 1
    fi
  }
  export -f curl
  export call_file

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: error message mentions GitHub or repo" {
  curl() {
    echo '{"object":{"sha":"null"}}'
  }
  export -f curl

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
  [[ "$output" == *"GitHub"* ]] || [[ "$output" == *"SHA"* ]] || [[ "$output" == *"branch"* ]] || [[ "$output" == *"fail"* ]] || [[ "$output" == *"Failed"* ]]
}
