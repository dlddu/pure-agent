#!/bin/bash
# Shared test helpers for e2e BATS tests.
# Usage: source "$BATS_TEST_DIRNAME/test-helper.sh"

E2E_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
LIB_DIR="$E2E_DIR/lib"

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

# Source assertions-argo.sh in --source-only mode.
load_assertions_argo() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/assertions-argo.sh" --source-only
}

# Source gatekeeper.sh in --source-only mode.
load_gatekeeper() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/gatekeeper.sh" --source-only
}

# Source mock-api.sh (mock-api helpers: wait_mock_api, reset_mock_api, configure_mock_llm_environment).
load_mock_api() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/mock-api.sh"
}

# Source mock-gh.sh (mock-gh helpers: count_gh_pr_create_calls, setup_mock_git_repo).
load_mock_gh() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/mock-gh.sh"
}

# Source common.sh (shared helpers: yaml_get, discover_scenarios, prepare_cycle_fixtures).
load_common() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/common.sh"
}

# Source localstack.sh in --source-only mode.
load_localstack() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/localstack.sh" --source-only
}

# Source Integration functions from run-integration.sh.
load_run_argo() {
  # Export variables that run-integration.sh reads at parse time.
  export SCRIPT_DIR="$E2E_DIR"
  export LIB_DIR="$LIB_DIR"
  export SCENARIOS_DIR="${SCENARIOS_DIR:-${E2E_DIR}/scenarios}"
  export LEVEL="${LEVEL:-2}"
  export NAMESPACE="${NAMESPACE:-pure-agent}"
  export KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"
  export MOCK_AGENT_IMAGE="${MOCK_AGENT_IMAGE:-ghcr.io/dlddu/pure-agent/e2e/mock-agent:latest}"
  export MOCK_API_URL="${MOCK_API_URL:-http://mock-api.pure-agent.svc.cluster.local:4000}"
  export WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"

  # shellcheck disable=SC1090
  source "$E2E_DIR/run-integration.sh" --source-only
}
