#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/setup-real.sh
#
# TDD Red Phase: setup-real.sh does not yet exist.
# These tests define the expected behaviour of:
#   setup_linear_test_issue <scenario_name>  -> prints Linear issue ID
#   setup_github_test_branch <scenario_name> -> prints branch name

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  # Provide required env vars so the sourced script does not die immediately.
  export LINEAR_API_KEY="test-linear-key"
  export LINEAR_TEAM_ID="test-team-id"
  export GITHUB_TOKEN="test-github-token"
  export GITHUB_TEST_REPO="testorg/testrepo"

  load_setup_real
}

# ── setup_linear_test_issue: happy path ───────────────────────────────────────

@test "setup_linear_test_issue: returns a non-empty issue ID on success" {
  # Arrange — mock curl to return a successful Linear GraphQL response
  curl() {
    echo '{"data":{"issueCreate":{"success":true,"issue":{"id":"abc-uuid-123","identifier":"TEST-42"}}}}'
  }
  export -f curl

  # Act
  run setup_linear_test_issue "report-action"

  # Assert
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "setup_linear_test_issue: output is the issue ID field from the API response" {
  # Arrange
  curl() {
    echo '{"data":{"issueCreate":{"success":true,"issue":{"id":"abc-uuid-123","identifier":"TEST-42"}}}}'
  }
  export -f curl

  # Act
  run setup_linear_test_issue "report-action"

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "abc-uuid-123" ]
}

@test "setup_linear_test_issue: issue title includes the scenario name" {
  # Arrange — capture the curl call arguments to verify the title
  local captured_body_file="$WORK_DIR/curl-body.json"

  curl() {
    # Write all args so we can inspect later; then return success response
    printf '%s\n' "$@" > "$captured_body_file"
    echo '{"data":{"issueCreate":{"success":true,"issue":{"id":"id-999","identifier":"TEST-99"}}}}'
  }
  export -f curl
  export captured_body_file

  # Act
  run setup_linear_test_issue "create-pr-action"

  # Assert
  [ "$status" -eq 0 ]
  grep -q "create-pr-action" "$captured_body_file"
}

# ── setup_linear_test_issue: error cases ──────────────────────────────────────

@test "setup_linear_test_issue: fails when LINEAR_API_KEY is not set" {
  unset LINEAR_API_KEY

  run setup_linear_test_issue "report-action"

  [ "$status" -ne 0 ]
}

@test "setup_linear_test_issue: fails when LINEAR_TEAM_ID is not set" {
  unset LINEAR_TEAM_ID

  run setup_linear_test_issue "report-action"

  [ "$status" -ne 0 ]
}

@test "setup_linear_test_issue: fails when curl returns a null issue id" {
  # Arrange — simulate API returning null (e.g. auth failure body)
  curl() {
    echo '{"data":{"issueCreate":{"success":false,"issue":null}}}'
  }
  export -f curl

  # Act
  run setup_linear_test_issue "report-action"

  # Assert — must exit non-zero (die)
  [ "$status" -ne 0 ]
}

@test "setup_linear_test_issue: fails when curl command itself fails" {
  # Arrange — mock curl to simulate network error
  curl() {
    return 1
  }
  export -f curl

  # Act
  run setup_linear_test_issue "report-action"

  # Assert
  [ "$status" -ne 0 ]
}

@test "setup_linear_test_issue: error message mentions failed issue creation" {
  curl() {
    echo '{"data":{"issueCreate":{"success":false,"issue":null}}}'
  }
  export -f curl

  run setup_linear_test_issue "report-action"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Linear"* ]] || [[ "$output" == *"issue"* ]] || [[ "$output" == *"fail"* ]] || [[ "$output" == *"Failed"* ]]
}

# ── setup_github_test_branch: happy path ──────────────────────────────────────

@test "setup_github_test_branch: returns a non-empty branch name on success" {
  # Arrange — first curl call returns base SHA, second creates the branch
  local call_count=0
  curl() {
    call_count=$((call_count + 1))
    if [ "$call_count" -eq 1 ]; then
      # GET /git/ref/heads/main -> base SHA
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      # POST /git/refs -> branch created (empty body on success)
      echo '{}'
    fi
  }
  export -f curl

  # Act
  run setup_github_test_branch "create-pr-action"

  # Assert
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "setup_github_test_branch: branch name contains the scenario name" {
  local call_count=0
  curl() {
    call_count=$((call_count + 1))
    if [ "$call_count" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      echo '{}'
    fi
  }
  export -f curl

  run setup_github_test_branch "create-pr-action"

  [ "$status" -eq 0 ]
  [[ "$output" == *"create-pr-action"* ]]
}

@test "setup_github_test_branch: branch name contains the e2e-test prefix" {
  local call_count=0
  curl() {
    call_count=$((call_count + 1))
    if [ "$call_count" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      echo '{}'
    fi
  }
  export -f curl

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
  local call_count=0
  curl() {
    call_count=$((call_count + 1))
    if [ "$call_count" -eq 1 ]; then
      return 1
    fi
    echo '{}'
  }
  export -f curl

  run setup_github_test_branch "create-pr-action"

  [ "$status" -ne 0 ]
}

@test "setup_github_test_branch: fails when branch creation curl call fails" {
  local call_count=0
  curl() {
    call_count=$((call_count + 1))
    if [ "$call_count" -eq 1 ]; then
      echo '{"object":{"sha":"deadbeef1234567890"}}'
    else
      return 1
    fi
  }
  export -f curl

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
