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

# Source assertions-argo.sh in --source-only mode.
load_assertions_argo() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/assertions-argo.sh" --source-only
}

# Source common.sh (shared helpers: yaml_get, discover_scenarios, prepare_cycle_fixtures).
load_common() {
  # shellcheck disable=SC1090
  source "$LIB_DIR/common.sh"
}

# Source Level-2 functions from run-argo.sh.
#
# run-argo.sh's --source-only guard fires BEFORE function definitions (line
# ~58), so sourcing with --source-only only loads the helper libraries
# (setup-real.sh, assertions-argo.sh, etc.) but NOT the functions defined
# after the guard (check_prerequisites, _level2_*, etc.).
#
# Strategy: set SCRIPT_DIR so run-argo.sh can locate its lib/ directory,
# then source each function-definition block directly after the guard.
# We do this by sourcing the helper libraries manually and then sourcing
# the run-argo.sh with a temporary override of the source guard variable.
load_run_argo() {
  local run_argo_dir
  run_argo_dir="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  local lib_dir="${run_argo_dir}/lib"
  local scenarios_dir="${run_argo_dir}/scenarios"

  # Export variables that run-argo.sh reads at parse time.
  export SCRIPT_DIR="$run_argo_dir"
  export LIB_DIR="$lib_dir"
  export SCENARIOS_DIR="${SCENARIOS_DIR:-$scenarios_dir}"
  export GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-test-org/test-repo}"
  export LEVEL="${LEVEL:-2}"
  export NAMESPACE="${NAMESPACE:-pure-agent}"
  export KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  export MOCK_AGENT_IMAGE="${MOCK_AGENT_IMAGE:-ghcr.io/dlddu/pure-agent/e2e/mock-agent:latest}"
  export MOCK_API_URL="${MOCK_API_URL:-http://mock-api.pure-agent.svc.cluster.local:4000}"
  export WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"

  # Source the shared libraries that run-argo.sh depends on.
  # shellcheck disable=SC1090
  source "$lib_dir/common.sh"
  # shellcheck disable=SC1090
  source "$lib_dir/setup-real.sh"    --source-only
  # shellcheck disable=SC1090
  source "$lib_dir/teardown-real.sh" --source-only
  # shellcheck disable=SC1090
  source "$lib_dir/verify-real.sh"   --source-only
  # shellcheck disable=SC1090
  source "$lib_dir/assertions-argo.sh" --source-only

  # Define local logging functions matching run-argo.sh so function bodies work.
  log()  { echo "[run-argo] $*" >&2; }
  warn() { echo "[run-argo] WARN: $*" >&2; }
  die()  { echo "[run-argo] ERROR: $*" >&2; return 1; }

  # Source only the function-definition sections of run-argo.sh by extracting
  # them from the file.  We strip:
  #   1. Everything up to and including the --source-only guard's closing fi.
  #   2. The top-level "main" discovery/dispatch loop at the end of the file.
  # shellcheck disable=SC1090
  local tmp_script
  tmp_script=$(mktemp)
  # Extract lines from "check_prerequisites()" onward, removing the final
  # `main "$@"` invocation so no side effects occur.
  awk '
    /^check_prerequisites\(\)/ { in_funcs=1 }
    in_funcs { print }
  ' "$run_argo_dir/run-argo.sh" \
    | sed 's/^main "\$@"$/: # removed/' \
    > "$tmp_script"

  # shellcheck disable=SC1090
  source "$tmp_script"
  rm -f "$tmp_script"
}
