#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for .github/workflows/e2e-level2.yaml — DLD-467 CI activation checks.
#
# Verifies that the workflow file no longer contains the "if: false" condition
# that disabled the e2e-level2 job during the DLD-466 stub phase.

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  E2E_LEVEL2_WORKFLOW="${REPO_ROOT}/.github/workflows/e2e-level2.yaml"
}

# ── if: false removal ─────────────────────────────────────────────────────────

@test "e2e-level2.yaml: does not contain 'if: false'" {
  # The job-level "if: false" gate must be removed so CI actually runs.
  run grep -n "if: false" "$E2E_LEVEL2_WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "e2e-level2.yaml: does not contain any always-false job condition" {
  # Guard against alternate spellings like 'if: "false"' or "if: 'false'".
  run grep -nE "if:\s+['\"]?false['\"]?" "$E2E_LEVEL2_WORKFLOW"
  [ "$status" -ne 0 ]
}

# ── File integrity: key sections are still present ───────────────────────────

@test "e2e-level2.yaml: file exists" {
  [ -f "$E2E_LEVEL2_WORKFLOW" ]
}

@test "e2e-level2.yaml: jobs section is present" {
  grep -q "^jobs:" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: e2e-level2 job is defined" {
  grep -q "e2e-level2:" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: on.push trigger is configured" {
  grep -q "^on:" "$E2E_LEVEL2_WORKFLOW"
  grep -q "push:" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: run-argo.sh is invoked with --level 2" {
  grep -q "run-argo.sh" "$E2E_LEVEL2_WORKFLOW"
  grep -q "\-\-level 2" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: kind cluster setup step is present" {
  grep -q "setup-kind.sh" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: kind cluster teardown step is present" {
  grep -q "kind delete cluster" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: runs-on is configured for a valid runner" {
  grep -q "runs-on:" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: MOCK_AGENT_IMAGE environment variable is set" {
  grep -q "MOCK_AGENT_IMAGE" "$E2E_LEVEL2_WORKFLOW"
}

@test "e2e-level2.yaml: MOCK_API_URL or mock-api reference is present" {
  grep -q "mock-api" "$E2E_LEVEL2_WORKFLOW"
}
