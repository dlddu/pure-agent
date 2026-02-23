#!/bin/bash
# Shared test helpers for e2e/lib BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

LIB_DIR="$BATS_TEST_DIRNAME/.."

common_setup() {
  export WORK_DIR="$BATS_TEST_TMPDIR/work"
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$WORK_DIR" "$FIXTURE_DIR"
}

# Source assertions.sh in --source-only mode so we can call individual
# functions without triggering any top-level side effects.
load_assertions() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/assertions.sh" --source-only
}

# Source runner.sh in --source-only mode.
load_runner() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/runner.sh" --source-only
}

# Source setup-real.sh in --source-only mode.
load_setup_real() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/setup-real.sh" --source-only
}

# Source teardown-real.sh in --source-only mode.
load_teardown_real() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/teardown-real.sh" --source-only
}

# Source verify-real.sh in --source-only mode.
load_verify_real() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/verify-real.sh" --source-only
}

# Source run-argo.sh in --source-only mode (Level 2 환경 변수 필요).
# 호출 전에 LEVEL=2, MOCK_AGENT_IMAGE, MOCK_API_IMAGE, GITHUB_TEST_REPO 등을 export해야 합니다.
load_run_argo() {
  local run_argo_sh
  run_argo_sh="$(cd "$LIB_DIR/../.." && pwd)/e2e/run-argo.sh"
  # shellcheck disable=SC1090
  source "$run_argo_sh" --source-only
}
