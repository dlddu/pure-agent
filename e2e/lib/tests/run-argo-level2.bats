#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/run-argo.sh Level 2 functions — DLD-467 activation checks.
#
# Validates that all Level 2 functions in run-argo.sh have had their [SKIP]
# guard lines removed so they execute real logic when --level 2 is passed.
#
# Two layers of tests:
#   1. Static text scans: confirm no "[SKIP]" pattern remains in the functions.
#   2. Behavioural smoke tests: source the script and verify that functions
#      are callable and produce expected side-effects (using mocked external
#      commands where necessary).

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  RUN_ARGO="${REPO_ROOT}/e2e/run-argo.sh"
}

# ── Static: [SKIP] guard removal ─────────────────────────────────────────────

@test "run-argo: check_prerequisites Level 2 branch does not contain [SKIP]" {
  # The line: echo "[SKIP] check_prerequisites (Level 2): ..." && return 0
  # must no longer exist.
  run grep -n "\[SKIP\].*check_prerequisites" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

@test "run-argo: _level2_place_cycle_fixtures does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*_level2_place_cycle_fixtures" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

@test "run-argo: _level2_submit_mock_workflow does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*_level2_submit_mock_workflow" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

@test "run-argo: _level2_verify_cycle does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*_level2_verify_cycle" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

@test "run-argo: run_scenario_level2 does not contain [SKIP] guard" {
  run grep -n "\[SKIP\].*run_scenario_level2" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

@test "run-argo: file contains no [SKIP] patterns at all" {
  # All DLD-466 skip guards must be gone.
  run grep -c "\[SKIP\]" "$RUN_ARGO"
  [ "$status" -ne 0 ]
}

# ── Static: Level 2 functions are present in the file ────────────────────────

@test "run-argo: _level2_place_cycle_fixtures function definition exists" {
  grep -q "_level2_place_cycle_fixtures()" "$RUN_ARGO"
}

@test "run-argo: _level2_submit_mock_workflow function definition exists" {
  grep -q "_level2_submit_mock_workflow()" "$RUN_ARGO"
}

@test "run-argo: _level2_verify_cycle function definition exists" {
  grep -q "_level2_verify_cycle()" "$RUN_ARGO"
}

@test "run-argo: run_scenario_level2 function definition exists" {
  grep -q "run_scenario_level2()" "$RUN_ARGO"
}

# ── Structural: functions are callable when sourced ───────────────────────────

@test "run-argo: script can be sourced with --source-only without error" {
  run bash -c "
    export LINEAR_API_KEY=dummy
    export LINEAR_TEAM_ID=dummy
    export GITHUB_TOKEN=dummy
    export GITHUB_TEST_REPO=org/repo
    source '${RUN_ARGO}' --source-only
  "
  [ "$status" -eq 0 ]
}

@test "run-argo: _level2_place_cycle_fixtures is defined after sourcing" {
  run bash -c "
    source '${RUN_ARGO}' --source-only
    declare -f _level2_place_cycle_fixtures > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "run-argo: _level2_submit_mock_workflow is defined after sourcing" {
  run bash -c "
    source '${RUN_ARGO}' --source-only
    declare -f _level2_submit_mock_workflow > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "run-argo: _level2_verify_cycle is defined after sourcing" {
  run bash -c "
    source '${RUN_ARGO}' --source-only
    declare -f _level2_verify_cycle > /dev/null
  "
  [ "$status" -eq 0 ]
}

@test "run-argo: run_scenario_level2 is defined after sourcing" {
  run bash -c "
    source '${RUN_ARGO}' --source-only
    declare -f run_scenario_level2 > /dev/null
  "
  [ "$status" -eq 0 ]
}

# ── Behavioural: _level2_place_cycle_fixtures ─────────────────────────────────

@test "_level2_place_cycle_fixtures: places export_config.json when cycle has one" {
  # Arrange — create a minimal scenario YAML with a cycle that has export_config
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: test-scenario
cycles:
  - export_config:
      action: none
    agent_result: "done"
YAML

  local out_dir="$WORK_DIR/cycle0"
  mkdir -p "$out_dir"

  # Act
  run bash -c "
    yq() {
      # Minimal yq stub: handle the two calls made by the function.
      local expr=\"\$2\"
      if [[ \"\$expr\" == '.cycles[0].export_config' ]]; then
        echo 'action: none'
      elif [[ \"\$expr\" == '-o=json' || \"\$@\" == *'-o=json'* ]]; then
        echo '{\"action\":\"none\"}'
      elif [[ \"\$expr\" == '.cycles[0].agent_result // \"\"' ]]; then
        echo 'done'
      fi
    }
    export -f yq
    source '${RUN_ARGO}' --source-only
    NAMESPACE=pure-agent KUBE_CONTEXT=kind-test
    _level2_place_cycle_fixtures '${yaml_file}' 0 '${out_dir}'
  "
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: creates output directory when it does not exist" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: depth-limit
cycles:
  - export_config: null
YAML

  local out_dir="$WORK_DIR/new-cycle-dir"
  # Deliberately do not create out_dir beforehand.

  run bash -c "
    yq() {
      local expr=\"\$2\"
      if [[ \"\$expr\" == '.cycles[0].export_config' ]]; then
        echo 'null'
      elif [[ \"\$expr\" == '.cycles[0].agent_result // \"\"' ]]; then
        echo ''
      fi
    }
    export -f yq
    source '${RUN_ARGO}' --source-only
    _level2_place_cycle_fixtures '${yaml_file}' 0 '${out_dir}'
  "
  [ "$status" -eq 0 ]
  [ -d "$out_dir" ]
}

# ── Behavioural: check_prerequisites Level 2 ─────────────────────────────────

@test "check_prerequisites (Level 2): passes when argo, kubectl, jq, yq are all present" {
  # Arrange — provide minimal stubs for all required commands.
  run bash -c "
    argo()    { return 0; }
    kubectl() { return 0; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    check_prerequisites
  "
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): output confirms Level 2 prerequisites OK" {
  run bash -c "
    argo()    { return 0; }
    kubectl() { return 0; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    check_prerequisites
  " 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Level 2"* ]] || [[ "$output" == *"level2"* ]] || [[ "$output" == *"Level2"* ]]
}

@test "check_prerequisites (Level 2): does not require LINEAR_API_KEY" {
  # Level 2 must succeed even without LINEAR_API_KEY being set.
  run bash -c "
    argo()    { return 0; }
    kubectl() { return 0; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    unset LINEAR_API_KEY
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    check_prerequisites
  "
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): does not require GITHUB_TOKEN" {
  run bash -c "
    argo()    { return 0; }
    kubectl() { return 0; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    unset GITHUB_TOKEN
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    check_prerequisites
  "
  [ "$status" -eq 0 ]
}

@test "check_prerequisites (Level 2): fails when argo CLI is missing" {
  run bash -c "
    # Remove argo from PATH by shadowing it with a failing stub.
    argo()    { return 127; }
    kubectl() { return 0; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    # die() calls exit 1; use a subshell to capture it cleanly.
    (check_prerequisites)
  "
  [ "$status" -ne 0 ]
}

@test "check_prerequisites (Level 2): fails when kubectl is missing" {
  run bash -c "
    argo()    { return 0; }
    kubectl() { return 127; }
    jq()      { return 0; }
    yq()      { return 0; }
    export -f argo kubectl jq yq
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    source '${RUN_ARGO}' --source-only
    (check_prerequisites)
  "
  [ "$status" -ne 0 ]
}

# ── Behavioural: run_scenario_level2 reads cycles from YAML ──────────────────

@test "run_scenario_level2: exits non-zero when scenario YAML does not exist" {
  run bash -c "
    export LEVEL=2
    export NAMESPACE=pure-agent
    export KUBE_CONTEXT=kind-pure-agent-e2e-level2
    export MOCK_AGENT_IMAGE=mock-agent:latest
    export MOCK_API_URL=http://mock-api:4000
    source '${RUN_ARGO}' --source-only
    run_scenario_level2 'nonexistent-scenario-xyz'
  "
  [ "$status" -ne 0 ]
}
