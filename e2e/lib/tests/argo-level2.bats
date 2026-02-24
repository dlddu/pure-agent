#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/lib/tests/argo-level2.bats
#
# DLD-466: Level ② E2E テスト (Argo 특화 검증)
#
# DLD-467: Level ② 구현 완료 — 모든 테스트가 활성화되어 있습니다.
#
# 전제:
#   - kind 클러스터가 실행 중이고 KUBE_CONTEXT 환경 변수가 설정되어 있어야 합니다.
#   - Argo Workflows가 argo 네임스페이스에 설치되어 있어야 합니다.
#   - pure-agent 네임스페이스에 mock WorkflowTemplate이 적용되어 있어야 합니다.
#   - argo, kubectl, jq CLI가 PATH에 있어야 합니다.
#
# 실행 방법 (구현 완료 후):
#   bats e2e/lib/tests/argo-level2.bats
#
# 환경 변수:
#   KUBE_CONTEXT      — kubectl context (기본값: kind-pure-agent-e2e)
#   NAMESPACE         — pure-agent 네임스페이스 (기본값: pure-agent)
#   WORKFLOW_TIMEOUT  — Workflow 완료 대기 시간(초) (기본값: 300)

source "$BATS_TEST_DIRNAME/test-helper.sh"

# ── 테스트 공통 설정 ──────────────────────────────────────────────────────────

setup() {
  common_setup

  # Level 2 테스트에서 사용할 환경 변수
  export KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e}"
  export NAMESPACE="${NAMESPACE:-pure-agent}"
  export WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-300}"

  # e2e 디렉토리 경로 (BATS_TEST_DIRNAME = e2e/lib/tests)
  E2E_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCENARIOS_DIR="${E2E_DIR}/scenarios"
  export E2E_DIR SCENARIOS_DIR
}

# ── 헬퍼 함수 ────────────────────────────────────────────────────────────────

# get_workflow_phase: Argo Workflow의 현재 상태(phase)를 반환합니다.
get_workflow_phase() {
  local workflow_name="$1"
  argo get "$workflow_name" \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    --output json \
    | jq -r '.status.phase // "Unknown"'
}

# wait_workflow: Workflow 완료까지 대기하고 최종 phase를 반환합니다.
wait_workflow() {
  local workflow_name="$1"
  timeout "${WORKFLOW_TIMEOUT}s" \
    argo wait "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" || true
  get_workflow_phase "$workflow_name"
}

# get_workflow_json: Workflow 전체 JSON을 반환합니다.
get_workflow_json() {
  local workflow_name="$1"
  argo get "$workflow_name" \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    --output json
}

# create_scenario_configmap: 시나리오 fixture 데이터를 ConfigMap으로 생성합니다.
# mock-agent가 SCENARIO_DIR에서 이 ConfigMap의 파일을 읽어 /work와 /tmp에 배치합니다.
create_scenario_configmap() {
  local scenario_name="$1"
  local cycle_index="${2:-0}"
  local scenario_yaml="${SCENARIOS_DIR}/${scenario_name}.yaml"

  local tmp_dir
  tmp_dir=$(mktemp -d)

  # export_config 추출
  local export_config
  export_config=$(yq eval ".cycles[${cycle_index}].export_config" "$scenario_yaml")
  if [[ "$export_config" != "null" && -n "$export_config" ]]; then
    echo "$export_config" | yq -o=json > "${tmp_dir}/export_config.json"
  fi

  # agent_result 추출
  local agent_result
  agent_result=$(yq eval ".cycles[${cycle_index}].agent_result // \"\"" "$scenario_yaml")
  if [[ -n "$agent_result" ]]; then
    echo "$agent_result" > "${tmp_dir}/agent_result.txt"
  fi

  # ConfigMap 생성/갱신
  local kubectl_args=()
  kubectl_args+=(--context "$KUBE_CONTEXT" -n "$NAMESPACE")
  kubectl_args+=(create configmap mock-scenario-data)

  if [[ -f "${tmp_dir}/export_config.json" ]]; then
    kubectl_args+=(--from-file="export_config.json=${tmp_dir}/export_config.json")
  fi
  if [[ -f "${tmp_dir}/agent_result.txt" ]]; then
    kubectl_args+=(--from-file="agent_result.txt=${tmp_dir}/agent_result.txt")
  fi
  kubectl_args+=(--dry-run=client -o yaml)

  kubectl "${kubectl_args[@]}" | kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" apply -f - >/dev/null

  rm -rf "$tmp_dir"
}

# submit_level2_scenario: Level 2 시나리오 fixture ConfigMap을 생성하고
# Workflow를 제출하여 이름을 반환합니다.
submit_level2_scenario() {
  local scenario_name="$1"
  local max_depth="${2:-5}"

  # 시나리오 fixture ConfigMap 생성 (mock-agent가 SCENARIO_DIR에서 읽음)
  create_scenario_configmap "$scenario_name" 0

  argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="mock-prompt-${scenario_name}" \
    --labels "e2e-level=2,e2e-scenario=${scenario_name}" \
    --output json \
    | jq -r '.metadata.name'
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Workflow 상태가 Succeeded인지 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "Level 2: report-action 시나리오 Workflow가 Succeeded 상태로 완료된다" {
  # Arrange: mock WorkflowTemplate이 클러스터에 적용되어 있어야 합니다.
  # (e2e/run-argo.sh --level 2 실행 시 patch_workflow_template_for_mock에 의해 적용됨)

  # Act: report-action 시나리오 Workflow 제출
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  # Workflow 완료 대기
  local phase
  phase=$(wait_workflow "$workflow_name")

  # Assert
  [ "$phase" = "Succeeded" ]
}

@test "Level 2: none-action 시나리오 Workflow가 Succeeded 상태로 완료된다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "none-action" 5)

  local phase
  phase=$(wait_workflow "$workflow_name")

  [ "$phase" = "Succeeded" ]
}

@test "Level 2: create-pr-action 시나리오 Workflow가 Succeeded 상태로 완료된다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "create-pr-action" 5)

  local phase
  phase=$(wait_workflow "$workflow_name")

  [ "$phase" = "Succeeded" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. MCP daemon, LLM gateway daemon pod이 정상 기동했는지 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "Level 2: report-action Workflow에서 mcp-daemon pod이 Running 상태로 기동된다" {
  # Arrange: Workflow 제출
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  # Workflow가 실행 중일 때 pod 상태를 확인합니다.
  # mcp-daemon은 daemon: true로 선언되어 있으므로 Workflow 실행 중 Running이어야 합니다.
  # argo wait 전에 pod 목록을 확인하기 위해 짧은 대기 후 조회합니다.
  sleep 10

  # Act: mcp-daemon 역할(pure-agent/role=mcp-server)을 가진 pod 조회
  local pod_count
  pod_count=$(kubectl get pods \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -l "workflows.argoproj.io/workflow=${workflow_name},pure-agent/role=mcp-server" \
    --field-selector "status.phase=Running" \
    -o json \
    | jq '.items | length')

  # Workflow 완료까지 대기 (정리 후 검증)
  wait_workflow "$workflow_name" > /dev/null

  # Assert: mcp-daemon pod이 최소 1개 이상 Running 상태로 기동되어야 합니다.
  [ "$pod_count" -ge 1 ]
}

@test "Level 2: report-action Workflow에서 llm-gateway-daemon pod이 Running 상태로 기동된다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  sleep 10

  # llm-gateway-daemon은 pure-agent/role=llm-gateway 레이블을 가집니다.
  # Level 2에서는 busybox sleep으로 교체되어 있으므로 Running 상태여야 합니다.
  local pod_count
  pod_count=$(kubectl get pods \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -l "workflows.argoproj.io/workflow=${workflow_name},pure-agent/role=llm-gateway" \
    --field-selector "status.phase=Running" \
    -o json \
    | jq '.items | length')

  wait_workflow "$workflow_name" > /dev/null

  [ "$pod_count" -ge 1 ]
}

@test "Level 2: Workflow status.nodes에 mcp-daemon과 llm-gateway-daemon 노드가 존재한다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  # status.nodes 중 displayName이 mcp-daemon인 노드가 있어야 합니다.
  local mcp_node_count
  mcp_node_count=$(echo "$workflow_json" \
    | jq '[.status.nodes[] | select(.displayName == "mcp-daemon")] | length')

  # status.nodes 중 displayName이 llm-gateway-daemon인 노드가 있어야 합니다.
  local llm_node_count
  llm_node_count=$(echo "$workflow_json" \
    | jq '[.status.nodes[] | select(.displayName == "llm-gateway-daemon")] | length')

  [ "$mcp_node_count" -ge 1 ]
  [ "$llm_node_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. continue-then-stop에서 run-cycle 재귀가 실제로 2회 실행됐는지 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "Level 2: continue-then-stop 시나리오에서 run-cycle이 정확히 2회 실행된다" {
  # Arrange: continue-then-stop 시나리오는 level [1, 2] 지원
  # cycle-0: continue → cycle-1: none(stop) 으로 run-cycle이 2회 실행되어야 합니다.
  local workflow_name
  workflow_name=$(submit_level2_scenario "continue-then-stop" 5)

  wait_workflow "$workflow_name" > /dev/null

  # Act: status.nodes에서 displayName이 "run-cycle"인 노드 수를 카운트합니다.
  # run-cycle은 재귀 호출되므로 Workflow DAG에 2개의 노드가 생성되어야 합니다.
  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  local run_cycle_count
  run_cycle_count=$(echo "$workflow_json" \
    | jq '[.status.nodes[] | select(.displayName | startswith("run-cycle"))] | length')

  # Assert: run-cycle 노드가 정확히 2개(depth 0 + depth 1) 존재해야 합니다.
  [ "$run_cycle_count" -eq 2 ]
}

@test "Level 2: continue-then-stop 시나리오에서 Workflow 최종 상태는 Succeeded이다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "continue-then-stop" 5)

  local phase
  phase=$(wait_workflow "$workflow_name")

  [ "$phase" = "Succeeded" ]
}

@test "Level 2: continue-then-stop에서 첫 번째 run-cycle 노드의 phase가 Succeeded이다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "continue-then-stop" 5)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  # run-cycle 노드 중 첫 번째(depth 0)의 phase 확인
  local first_cycle_phase
  first_cycle_phase=$(echo "$workflow_json" \
    | jq -r '[.status.nodes[] | select(.displayName | startswith("run-cycle"))]
              | sort_by(.startedAt)
              | .[0].phase')

  [ "$first_cycle_phase" = "Succeeded" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. depth-limit 시나리오에서 max_depth 종료가 Workflow 레벨에서 올바르게 처리
# ═══════════════════════════════════════════════════════════════════════════════

@test "Level 2: depth-limit 시나리오에서 max_depth=2로 제출한 Workflow가 Succeeded로 완료된다" {
  # depth-limit 시나리오는 export_config=null, max_depth=2로 설정됩니다.
  # Router가 max_depth에 도달하면 continue=false를 반환하여 루프가 종료됩니다.
  # Workflow 전체는 Succeeded로 완료되어야 합니다 (에러가 아닌 정상 종료).
  local workflow_name
  workflow_name=$(submit_level2_scenario "depth-limit" 2)

  local phase
  phase=$(wait_workflow "$workflow_name")

  [ "$phase" = "Succeeded" ]
}

@test "Level 2: depth-limit 시나리오에서 run-cycle의 recurse 단계가 실행되지 않는다" {
  # max_depth=2, cycles=1(export_config=null)이므로 router가 continue=false를 반환합니다.
  # run-cycle의 recurse 단계는 when 조건(continue==true)이 false이므로 Skipped 상태여야 합니다.
  local workflow_name
  workflow_name=$(submit_level2_scenario "depth-limit" 2)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  # recurse 단계(displayName="recurse")의 phase가 Skipped이어야 합니다.
  local recurse_phase
  recurse_phase=$(echo "$workflow_json" \
    | jq -r '[.status.nodes[] | select(.displayName == "recurse")]
              | .[0].phase // "Skipped"')

  [ "$recurse_phase" = "Skipped" ]
}

@test "Level 2: depth-limit 시나리오에서 run-cycle 노드는 정확히 1개만 존재한다" {
  # max_depth 도달 시 재귀 호출 없이 1회만 실행되어야 합니다.
  local workflow_name
  workflow_name=$(submit_level2_scenario "depth-limit" 2)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  local run_cycle_count
  run_cycle_count=$(echo "$workflow_json" \
    | jq '[.status.nodes[] | select(.displayName | startswith("run-cycle"))] | length')

  [ "$run_cycle_count" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Cleanup job 이후 /work가 비어있는지 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "Level 2: report-action Workflow의 cleanup-job 완료 후 /work 디렉토리가 비어있다" {
  # Arrange: Workflow 실행 후 cleanup-job의 출력 파라미터를 검증합니다.
  # cleanup-job은 `find /work -maxdepth 1 | tee /tmp/file_list.txt && find /work -mindepth 1 -delete`
  # 를 실행합니다. file_list.txt에는 삭제 전 파일 목록이 기록됩니다.
  # cleanup 완료 후 /work에는 아무 파일도 없어야 합니다.
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  # Act: cleanup-job 노드의 outputs.parameters에서 file_list 값을 가져옵니다.
  # file_list에는 `find /work -maxdepth 1` 결과가 들어 있으며,
  # cleanup 후에는 /work 자체만 남아 있어야 합니다(빈 디렉토리).
  local file_list_output
  file_list_output=$(echo "$workflow_json" \
    | jq -r '.status.nodes[]
              | select(.displayName == "cleanup")
              | .outputs.parameters[]
              | select(.name == "file_list")
              | .value // ""')

  # Assert: file_list에는 /work 한 줄만 존재해야 합니다 (하위 파일 없음).
  # find /work -maxdepth 1 은 /work 자체도 포함하므로 line count == 1
  local line_count
  line_count=$(echo "$file_list_output" | grep -c '.' || true)

  [ "$line_count" -eq 1 ]
}

@test "Level 2: none-action Workflow의 cleanup-job 완료 후 /work 디렉토리가 비어있다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "none-action" 5)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  local file_list_output
  file_list_output=$(echo "$workflow_json" \
    | jq -r '.status.nodes[]
              | select(.displayName == "cleanup")
              | .outputs.parameters[]
              | select(.name == "file_list")
              | .value // ""')

  local line_count
  line_count=$(echo "$file_list_output" | grep -c '.' || true)

  [ "$line_count" -eq 1 ]
}

@test "Level 2: cleanup-job 노드가 Workflow status.nodes에 Succeeded 상태로 존재한다" {
  local workflow_name
  workflow_name=$(submit_level2_scenario "report-action" 5)

  wait_workflow "$workflow_name" > /dev/null

  local workflow_json
  workflow_json=$(get_workflow_json "$workflow_name")

  # cleanup 노드(displayName="cleanup")의 phase가 Succeeded이어야 합니다.
  local cleanup_phase
  cleanup_phase=$(echo "$workflow_json" \
    | jq -r '[.status.nodes[] | select(.displayName == "cleanup")]
              | .[0].phase // "NotFound"')

  [ "$cleanup_phase" = "Succeeded" ]
}
