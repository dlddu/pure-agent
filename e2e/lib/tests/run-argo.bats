#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/run-argo.sh — Level ② skip 함수 unit 테스트
#
# DLD-467: Level ② kind + Argo CI 테스트 활성화.
#
# 검증 대상:
#   - check_prerequisites (Level 2 분기)
#   - _level2_place_cycle_fixtures
#   - _level2_submit_mock_workflow
#   - _level2_verify_cycle
#   - run_scenario_level2
#
# 주의: run-argo.sh의 source guard는 --source-only 시 함수 정의 이전에 return합니다.
# 따라서 각 테스트는 `run bash -c "source run-argo.sh && function_call"` 패턴을 사용하여
# subshell에서 실행합니다. (runner.bats의 setup_scenario_env 테스트와 동일한 패턴)
#
# 실제 argo/kubectl/kind 없이 실행 가능하도록 mock 함수를 사용합니다.

source "$BATS_TEST_DIRNAME/test-helper.sh"

# ── 공통 환경 스니펫 ──────────────────────────────────────────────────────────
# 각 테스트에서 run bash -c "..." 에 삽입할 공통 환경 설정.
# run-argo.sh 로드 시 LEVEL=2로 설정하여 GITHUB_TEST_REPO 필수 체크를 우회합니다.

RUN_ARGO_SCRIPT="$LIB_DIR/../run-argo.sh"

# assertion 함수들의 stub을 환경변수로 주입하기 위한 헬퍼
_stub_assertions_and_helpers() {
  cat <<'STUBS'
assert_workflow_succeeded()   { return 0; }
assert_daemon_pods_ready()    { return 0; }
assert_run_cycle_count()      { return 0; }
assert_max_depth_termination() { return 0; }
assert_work_dir_clean()       { return 0; }
assert_mock_api()             { return 0; }
setup_linear_test_issue()     { echo "stub-issue-id"; }
setup_github_test_branch()    { echo "stub-branch-name"; }
teardown_linear_issue()       { return 0; }
teardown_github_pr_and_branch() { return 0; }
verify_linear_comment()       { return 0; }
verify_github_pr()            { return 0; }
STUBS
}

setup() {
  common_setup

  # 기본 환경 변수 (subshell에 전달)
  export NAMESPACE="pure-agent"
  export KUBE_CONTEXT="kind-pure-agent-e2e-level2"
  export MOCK_AGENT_IMAGE="ghcr.io/dlddu/pure-agent/mock-agent:latest"
  export MOCK_API_URL="http://mock-api.pure-agent.svc.cluster.local:4000"
  export WORKFLOW_TIMEOUT="300"
  export LEVEL="2"
}

# ── check_prerequisites (Level 2 분기) ───────────────────────────────────────

@test "check_prerequisites: Level 2 passes when argo/kubectl/jq/yq are all present" {
  if ! command -v argo >/dev/null 2>&1 \
    || ! command -v kubectl >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1 \
    || ! command -v yq >/dev/null 2>&1; then
    skip "argo/kubectl/jq/yq not installed — skipping prerequisites test"
  fi

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    check_prerequisites
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "check_prerequisites Level 2 branch is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "check_prerequisites: Level 2 does NOT require LINEAR_API_KEY" {
  if ! command -v argo >/dev/null 2>&1 \
    || ! command -v kubectl >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1 \
    || ! command -v yq >/dev/null 2>&1; then
    skip "argo/kubectl/jq/yq not installed — skipping prerequisites test"
  fi

  run bash -c "
    export LEVEL=2
    unset LINEAR_API_KEY
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    check_prerequisites
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "check_prerequisites Level 2 branch is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "check_prerequisites: Level 2 does NOT require GITHUB_TOKEN" {
  if ! command -v argo >/dev/null 2>&1 \
    || ! command -v kubectl >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1 \
    || ! command -v yq >/dev/null 2>&1; then
    skip "argo/kubectl/jq/yq not installed — skipping prerequisites test"
  fi

  run bash -c "
    export LEVEL=2
    unset GITHUB_TOKEN
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    check_prerequisites
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "check_prerequisites Level 2 branch is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

# ── _level2_place_cycle_fixtures ──────────────────────────────────────────────

@test "_level2_place_cycle_fixtures: places export_config.json when cycles[0].export_config is set" {
  # Arrange
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
cycles:
  - export_config:
      linear_issue_id: "mock-issue-id"
      actions:
        - "none"
    agent_result: "Task completed."
YAML

  local target_dir="$BATS_TEST_TMPDIR/cycle0"
  mkdir -p "$target_dir"

  # Act
  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '0' '$target_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$target_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: export_config.json is valid JSON after placement" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
cycles:
  - export_config:
      linear_issue_id: "mock-issue-id"
      actions:
        - "none"
    agent_result: "done"
YAML

  local target_dir="$BATS_TEST_TMPDIR/cycle0-json"
  mkdir -p "$target_dir"

  bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '0' '$target_dir'
  " 2>/dev/null || true

  if [[ ! -f "$target_dir/export_config.json" ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  # export_config.json이 유효한 JSON인지 검증
  run jq empty "$target_dir/export_config.json"
  [ "$status" -eq 0 ]
}

@test "_level2_place_cycle_fixtures: places agent_result.txt when cycles[0].agent_result is set" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
cycles:
  - export_config:
      actions: ["none"]
    agent_result: "Task completed successfully."
YAML

  local target_dir="$BATS_TEST_TMPDIR/cycle0-agent"
  mkdir -p "$target_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '0' '$target_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$target_dir/agent_result.txt" ]
  run cat "$target_dir/agent_result.txt"
  [[ "$output" == *"Task completed successfully."* ]]
}

@test "_level2_place_cycle_fixtures: does NOT create export_config.json when cycles[0].export_config is null" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: depth-limit
cycles:
  - export_config: null
    agent_result: "Depth limit reached"
YAML

  local target_dir="$BATS_TEST_TMPDIR/cycle0-null"
  mkdir -p "$target_dir"
  rm -f "$target_dir/export_config.json"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '0' '$target_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ ! -f "$target_dir/export_config.json" ]
}

@test "_level2_place_cycle_fixtures: picks up the correct cycle index" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: continue-then-stop
cycles:
  - export_config:
      actions: ["continue"]
    agent_result: "cycle 0 result"
  - export_config:
      actions: ["none"]
    agent_result: "cycle 1 done"
YAML

  local target_dir="$BATS_TEST_TMPDIR/cycle1"
  mkdir -p "$target_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '1' '$target_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$target_dir/agent_result.txt" ]

  # cycle 1의 agent_result가 올바르게 배치됐는지 확인
  run cat "$target_dir/agent_result.txt"
  [[ "$output" == *"cycle 1"* ]]
}

@test "_level2_place_cycle_fixtures: creates target_dir if it does not exist" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
cycles:
  - export_config:
      actions: ["none"]
    agent_result: "done"
YAML

  local target_dir="$BATS_TEST_TMPDIR/nonexistent-place/cycle0"
  # 의도적으로 디렉토리를 만들지 않음
  rm -rf "$target_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)
    source '$RUN_ARGO_SCRIPT'
    _level2_place_cycle_fixtures '$yaml_file' '0' '$target_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_place_cycle_fixtures is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -d "$target_dir" ]
}

# ── _level2_submit_mock_workflow ───────────────────────────────────────────────

@test "_level2_submit_mock_workflow: returns a non-empty workflow name on success" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-test"
  mkdir -p "$scenario_dir"
  echo '{"actions":["none"]}' > "$scenario_dir/export_config.json"
  echo "Task done." > "$scenario_dir/agent_result.txt"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    # mock kubectl and argo
    kubectl() { return 0; }
    argo() {
      case \"\$1\" in
        submit) echo '{\"metadata\":{\"name\":\"pure-agent-mock123\"}}' ;;
        wait)   return 0 ;;
        get)    echo '{\"status\":{\"phase\":\"Succeeded\"}}' ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    _level2_submit_mock_workflow 'none-action' '0' '5' '$scenario_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "_level2_submit_mock_workflow: output is the submitted workflow name" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-name-test"
  mkdir -p "$scenario_dir"
  echo '{}' > "$scenario_dir/export_config.json"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    argo() {
      case \"\$1\" in
        submit) echo '{\"metadata\":{\"name\":\"pure-agent-testname99\"}}' ;;
        wait)   return 0 ;;
        get)    echo '{\"status\":{\"phase\":\"Succeeded\"}}' ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    # stderr 제거하여 stdout(workflow name)만 캡처
    _level2_submit_mock_workflow 'none-action' '0' '5' '$scenario_dir' 2>/dev/null
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ "$output" = "pure-agent-testname99" ]
}

@test "_level2_submit_mock_workflow: creates a ConfigMap with a sanitised name" {
  local cm_name_file="$WORK_DIR/cm-name.txt"
  local scenario_dir="$BATS_TEST_TMPDIR/submit-cm-test"
  mkdir -p "$scenario_dir"
  echo '{}' > "$scenario_dir/export_config.json"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    kubectl() {
      if [[ \"\$1\" == 'create' ]] && [[ \"\$2\" == 'configmap' ]]; then
        echo \"\$3\" > '$cm_name_file'
      fi
      return 0
    }
    argo() {
      case \"\$1\" in
        submit) echo '{\"metadata\":{\"name\":\"pure-agent-abc\"}}' ;;
        wait)   return 0 ;;
        get)    echo '{\"status\":{\"phase\":\"Succeeded\"}}' ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    _level2_submit_mock_workflow 'none-action' '0' '5' '$scenario_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]

  if [[ -f "$cm_name_file" ]]; then
    local cm_name
    cm_name=$(cat "$cm_name_file")
    # ConfigMap 이름은 소문자와 하이픈만 허용
    [[ "$cm_name" =~ ^[a-z0-9-]+$ ]]
  fi
}

@test "_level2_submit_mock_workflow: fails when argo submit fails" {
  local scenario_dir="$BATS_TEST_TMPDIR/submit-fail-test"
  mkdir -p "$scenario_dir"
  echo '{}' > "$scenario_dir/export_config.json"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    argo() {
      case \"\$1\" in
        submit) return 1 ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    _level2_submit_mock_workflow 'none-action' '0' '5' '$scenario_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "_level2_submit_mock_workflow: includes scenario_name in prompt parameter" {
  local argo_args_file="$WORK_DIR/argo-args.txt"
  local scenario_dir="$BATS_TEST_TMPDIR/submit-args-test"
  mkdir -p "$scenario_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    argo() {
      case \"\$1\" in
        submit)
          printf '%s\n' \"\$@\" >> '$argo_args_file'
          echo '{\"metadata\":{\"name\":\"pure-agent-abc\"}}'
          ;;
        wait) return 0 ;;
        get)  echo '{\"status\":{\"phase\":\"Succeeded\"}}' ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    _level2_submit_mock_workflow 'create-pr-action' '0' '5' '$scenario_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]

  if [[ -f "$argo_args_file" ]]; then
    grep -q "create-pr-action" "$argo_args_file"
  fi
}

@test "_level2_submit_mock_workflow: passes max_depth to argo submit" {
  local argo_args_file="$WORK_DIR/argo-maxdepth.txt"
  local scenario_dir="$BATS_TEST_TMPDIR/submit-maxdepth-test"
  mkdir -p "$scenario_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export WORKFLOW_TIMEOUT=300
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    argo() {
      case \"\$1\" in
        submit)
          printf '%s\n' \"\$@\" >> '$argo_args_file'
          echo '{\"metadata\":{\"name\":\"pure-agent-abc\"}}'
          ;;
        wait) return 0 ;;
        get)  echo '{\"status\":{\"phase\":\"Succeeded\"}}' ;;
      esac
    }

    source '$RUN_ARGO_SCRIPT'
    _level2_submit_mock_workflow 'depth-limit' '0' '2' '$scenario_dir'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_submit_mock_workflow is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]

  if [[ -f "$argo_args_file" ]]; then
    grep -q "2" "$argo_args_file"
  fi
}

# ── _level2_verify_cycle ──────────────────────────────────────────────────────

@test "_level2_verify_cycle: passes for none-action scenario with stop router_decision" {
  local yaml_file="$FIXTURE_DIR/none-action.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
assertions:
  router_decision: "stop"
  export_handler_exit: 0
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "_level2_verify_cycle: passes for report-action scenario with linear_comment assertion" {
  local yaml_file="$FIXTURE_DIR/report-action.yaml"
  cat > "$yaml_file" <<'YAML'
name: report-action
assertions:
  router_decision: "stop"
  export_handler_exit: 0
  linear_comment:
    body_contains: "분析 리포트"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "_level2_verify_cycle: passes for create-pr-action scenario with github_pr assertion" {
  local yaml_file="$FIXTURE_DIR/create-pr-action.yaml"
  cat > "$yaml_file" <<'YAML'
name: create-pr-action
assertions:
  router_decision: "stop"
  github_pr: true
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "_level2_verify_cycle: passes for continue-then-stop cycle 0 with router_decisions[0]" {
  local yaml_file="$FIXTURE_DIR/continue-then-stop.yaml"
  cat > "$yaml_file" <<'YAML'
name: continue-then-stop
assertions:
  router_decisions:
    - "continue"
    - "stop"
  export_handler_exit: 0
  linear_comment:
    body_contains: "작업 완료"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "_level2_verify_cycle: fails when assert_workflow_succeeded fails" {
  local yaml_file="$FIXTURE_DIR/none-action.yaml"
  cat > "$yaml_file" <<'YAML'
name: none-action
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    # Override: make assert_workflow_succeeded fail
    assert_workflow_succeeded() { return 1; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "_level2_verify_cycle: fails when assert_mock_api fails for router_decision" {
  local yaml_file="$FIXTURE_DIR/report-action.yaml"
  cat > "$yaml_file" <<'YAML'
name: report-action
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    $(_stub_assertions_and_helpers)

    # Override: make assert_mock_api fail
    assert_mock_api() { return 1; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    _level2_verify_cycle '$yaml_file' 'pure-agent-abc12' '0'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "_level2_verify_cycle is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

# ── run_scenario_level2 ───────────────────────────────────────────────────────

@test "run_scenario_level2: returns 0 for none-action scenario" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"

  cat > "$scenarios_dir/none-action.yaml" <<'YAML'
name: none-action
max_depth: 5
cycles:
  - export_config:
      actions: ["none"]
    agent_result: "Task completed."
assertions:
  router_decision: "stop"
  export_handler_exit: 0
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    # Stub internal level2 functions
    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'none-action'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: returns 0 for continue-then-stop (2 cycles)" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"

  cat > "$scenarios_dir/continue-then-stop.yaml" <<'YAML'
name: continue-then-stop
cycles:
  - export_config:
      actions: ["continue"]
    agent_result: "cycle 0 done"
  - export_config:
      actions: ["none"]
    agent_result: "cycle 1 done"
assertions:
  router_decisions:
    - "continue"
    - "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'continue-then-stop'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: returns 0 for depth-limit scenario with max_depth=2" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"

  cat > "$scenarios_dir/depth-limit.yaml" <<'YAML'
name: depth-limit
max_depth: 2
cycles:
  - export_config: null
    agent_result: "Depth limit reached"
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'depth-limit'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi
  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: fails when scenario YAML does not exist" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'nonexistent-scenario'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi
  [ "$status" -ne 0 ]
}

@test "run_scenario_level2: warns and skips when no cycles are defined" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"

  cat > "$scenarios_dir/empty-cycles.yaml" <<'YAML'
name: empty-cycles
cycles: []
assertions: {}
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'empty-cycles'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi
  # 빈 cycles이면 warn하고 정상 종료(0)해야 함
  [ "$status" -eq 0 ]
}

@test "run_scenario_level2: calls assert_run_cycle_count for continue-then-stop scenario" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"
  local called_file="$WORK_DIR/run-cycle-count-called.txt"

  cat > "$scenarios_dir/continue-then-stop.yaml" <<'YAML'
name: continue-then-stop
cycles:
  - export_config:
      actions: ["continue"]
    agent_result: "cycle 0"
  - export_config:
      actions: ["none"]
    agent_result: "cycle 1"
assertions:
  router_decisions:
    - "continue"
    - "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    # Override assert_run_cycle_count to record the call
    assert_run_cycle_count() { touch '$called_file'; return 0; }

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'continue-then-stop'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$called_file" ]
}

@test "run_scenario_level2: calls assert_max_depth_termination for depth-limit scenario" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"
  local called_file="$WORK_DIR/max-depth-called.txt"

  cat > "$scenarios_dir/depth-limit.yaml" <<'YAML'
name: depth-limit
max_depth: 2
cycles:
  - export_config: null
    agent_result: "Depth reached"
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    assert_max_depth_termination() { touch '$called_file'; return 0; }

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'depth-limit'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$called_file" ]
}

@test "run_scenario_level2: calls assert_daemon_pods_ready for all workflows" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"
  local called_file="$WORK_DIR/daemon-called.txt"

  cat > "$scenarios_dir/none-action.yaml" <<'YAML'
name: none-action
cycles:
  - export_config:
      actions: ["none"]
    agent_result: "done"
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    assert_daemon_pods_ready() { touch '$called_file'; return 0; }

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'none-action'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$called_file" ]
}

@test "run_scenario_level2: calls assert_work_dir_clean for all workflows" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"
  local called_file="$WORK_DIR/work-clean-called.txt"

  cat > "$scenarios_dir/none-action.yaml" <<'YAML'
name: none-action
cycles:
  - export_config:
      actions: ["none"]
    agent_result: "done"
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    assert_work_dir_clean() { touch '$called_file'; return 0; }

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }
    curl() { return 0; }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'none-action'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$called_file" ]
}

@test "run_scenario_level2: resets mock-api assertions before running scenario" {
  local scenarios_dir="$FIXTURE_DIR/scenarios"
  mkdir -p "$scenarios_dir"
  local reset_called_file="$WORK_DIR/mock-api-reset.txt"

  cat > "$scenarios_dir/report-action.yaml" <<'YAML'
name: report-action
cycles:
  - export_config:
      actions: ["report"]
    agent_result: "report done"
assertions:
  router_decision: "stop"
YAML

  run bash -c "
    export LEVEL=2
    export NAMESPACE='pure-agent'
    export KUBE_CONTEXT='kind-test'
    export MOCK_AGENT_IMAGE='mock/agent:latest'
    export MOCK_API_URL='http://localhost:4000'
    export SCENARIOS_DIR='$scenarios_dir'
    $(_stub_assertions_and_helpers)

    _level2_place_cycle_fixtures() { return 0; }
    _level2_submit_mock_workflow()  { echo 'pure-agent-stub-wf'; }
    _level2_verify_cycle()          { return 0; }

    # Monitor reset call
    curl() {
      if [[ \"\$*\" == *'reset'* ]]; then
        touch '$reset_called_file'
      fi
      return 0
    }

    kubectl() { return 0; }
    source '$RUN_ARGO_SCRIPT'
    run_scenario_level2 'report-action'
  "

  if [[ "$output" == *"[SKIP]"* ]]; then
    skip "run_scenario_level2 is still skipped — remove skip line to activate"
  fi

  [ "$status" -eq 0 ]
  [ -f "$reset_called_file" ]
}
