#!/usr/bin/env bash
# e2e/run-argo.sh — Level ②③ E2E runner: kind + Argo Workflows
#
# DLD-465: Level ③ 풀 e2e를 실제로 동작하게 구현.
# DLD-466: Level ② e2e 테스트 추가 (mock-agent + mock-api 이미지 사용).
#
# 시나리오 정의는 e2e/scenarios/<name>.yaml 파일에서 읽습니다.
# YAML의 real.setup/teardown/max_depth 및 assertions 섹션을 사용하여
# 제네릭하게 시나리오를 실행합니다.
#
# Level ②: mock-agent + mock-api 이미지를 WorkflowTemplate에 주입하여 실행.
#           실제 Claude Agent / Linear API 없이 kind + Argo 레이어를 검증합니다.
# Level ③: 실제 Claude Agent + 실제 Linear/GitHub API로 시나리오를 실행합니다.
#
# Usage:
#   ./e2e/run-argo.sh [--scenario <name|all>] [--level <2|3>] [--namespace <ns>]
#
# Environment variables (required for Level 3):
#   LINEAR_API_KEY        — Linear Personal API Key
#   LINEAR_TEAM_ID        — Linear Team ID
#   GITHUB_TOKEN          — GitHub token (repo scope, PR 생성용)
#   GITHUB_TEST_REPO      — "org/repo" 형태의 테스트용 GitHub 레포
#   KUBE_CONTEXT          — kubectl context (기본값: kind-pure-agent-e2e-full)
#
# Environment variables (required for Level 2):
#   MOCK_AGENT_IMAGE      — mock-agent 컨테이너 이미지 (기본값: pure-agent/mock-agent:e2e)
#   MOCK_API_IMAGE        — mock-api 컨테이너 이미지 (기본값: pure-agent/mock-api:e2e)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-3}"
NAMESPACE="${NAMESPACE:-pure-agent}"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-pure-agent-e2e-full}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-600}"  # seconds

# ── Level 2 image defaults ────────────────────────────────────────────────────
# Level ②에서는 실제 Agent / MCP / LLM-gateway 이미지 대신 mock 이미지를 사용합니다.
MOCK_AGENT_IMAGE="${MOCK_AGENT_IMAGE:-pure-agent/mock-agent:e2e}"
MOCK_API_IMAGE="${MOCK_API_IMAGE:-pure-agent/mock-api:e2e}"

# ── Level 3 전용 환경 변수 (Level 2에서는 불필요) ─────────────────────────────
if [[ "${LEVEL}" -eq 3 ]]; then
  GITHUB_TEST_REPO="${GITHUB_TEST_REPO:?GITHUB_TEST_REPO is not set}"
else
  GITHUB_TEST_REPO="${GITHUB_TEST_REPO:-}"
fi
GITHUB_TEST_BRANCH_PREFIX="e2e-test"

# ── Source shared libraries ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
# shellcheck source=lib/setup-real.sh
source "$LIB_DIR/setup-real.sh" --source-only
# shellcheck source=lib/teardown-real.sh
source "$LIB_DIR/teardown-real.sh" --source-only
# shellcheck source=lib/verify-real.sh
source "$LIB_DIR/verify-real.sh" --source-only
# shellcheck source=lib/assertions.sh
source "$LIB_DIR/assertions.sh" --source-only

# ── Logging (override library prefixes) ──────────────────────────────────────
log()  { echo "[run-argo] $*" >&2; }
warn() { echo "[run-argo] WARN: $*" >&2; }
die()  { echo "[run-argo] ERROR: $*" >&2; exit 1; }

# ── Source guard (must be before arg parsing) ────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || true
fi

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)   SCENARIO="$2";   shift 2 ;;
    --level)      LEVEL="$2";      shift 2 ;;
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --context)    KUBE_CONTEXT="$2"; shift 2 ;;
    *)            die "Unknown argument: $1" ;;
  esac
done

# ── Prerequisites check ──────────────────────────────────────────────────────
check_prerequisites() {
  command -v argo    >/dev/null 2>&1 || die "argo CLI is not installed"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"
  command -v curl    >/dev/null 2>&1 || die "curl is not installed"
  command -v jq      >/dev/null 2>&1 || die "jq is not installed"
  command -v yq      >/dev/null 2>&1 || die "yq is not installed"

  if [[ "${LEVEL}" -eq 3 ]]; then
    [[ -n "${LINEAR_API_KEY:-}" ]]  || die "LINEAR_API_KEY is not set"
    [[ -n "${LINEAR_TEAM_ID:-}" ]]  || die "LINEAR_TEAM_ID is not set"
    [[ -n "${GITHUB_TOKEN:-}" ]]    || die "GITHUB_TOKEN is not set"
  fi

  log "Prerequisites OK"
}

# ── YAML helper ──────────────────────────────────────────────────────────────
# yq wrapper with null → empty string conversion.
yaml_get() {
  local yaml_file="$1"
  local path="$2"
  local value
  value=$(yq eval "$path" "$yaml_file")
  if [[ "$value" == "null" ]]; then
    echo ""
  else
    echo "$value"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# LEVEL 2: WORKFLOWTEMPLATE PATCHING
# ═══════════════════════════════════════════════════════════════════════════════

# patch_workflow_template_for_mock: Level ②용 WorkflowTemplate 패치를 적용합니다.
#
# Level ③ WorkflowTemplate에서 실제 이미지를 mock 이미지로 교체하고,
# kind 클러스터 호환성 패치(PNS executor, RWO, IfNotPresent)를 함께 적용합니다.
#
# 인자:
#   $1  src_template   — 원본 WorkflowTemplate YAML 경로
#   $2  dst_template   — 패치된 WorkflowTemplate 저장 경로
#   $3  scenario_name  — 시나리오 이름 (로그용)
patch_workflow_template_for_mock() {
  local src_template="$1"
  local dst_template="$2"
  local scenario_name="$3"

  log "Patching WorkflowTemplate for Level 2 mock (scenario=$scenario_name)"
  cp "$src_template" "$dst_template"

  # ── kind 호환성 패치 ──────────────────────────────────────────────────────
  # kind는 containerd 기반이므로 PNS executor 사용 (Docker executor 미지원)
  # storageClassName: efs → standard (kind local-path provisioner)
  sed -i 's/storageClassName: efs/storageClassName: standard/' "$dst_template"
  # ReadWriteMany → ReadWriteOnce (kind local-path는 RWO만 지원)
  sed -i 's/ReadWriteMany/ReadWriteOnce/' "$dst_template"
  # nodeSelector / tolerations 제거 (kind 클러스터에는 해당 레이블 없음)
  yq -i 'del(.spec.templates[].nodeSelector)' "$dst_template"
  yq -i 'del(.spec.templates[].tolerations)'  "$dst_template"
  # 이미지 pullPolicy를 IfNotPresent로 설정 (로컬 로드 이미지 사용)
  yq -i '(.spec.templates[] | select(has("container")) | .container.imagePullPolicy) = "IfNotPresent"' \
    "$dst_template"

  # ── mock 이미지 주입 ──────────────────────────────────────────────────────
  # agent-job 컨테이너를 mock-agent로 교체합니다.
  # mock-agent는 SCENARIO_DIR의 fixture를 읽어 /work에 배치하고 종료합니다.
  yq -i "(.spec.templates[] | select(.name == \"agent-job\") | .container.image) = \"${MOCK_AGENT_IMAGE}\"" \
    "$dst_template"
  yq -i "(.spec.templates[] | select(.name == \"agent-job\") | .container.command) = [\"/app/entrypoint.sh\"]" \
    "$dst_template"

  # mcp-daemon을 mock-api로 교체합니다.
  # mock-api는 Linear GraphQL mock 서버로 동작합니다.
  yq -i "(.spec.templates[] | select(.name == \"mcp-daemon\") | .container.image) = \"${MOCK_API_IMAGE}\"" \
    "$dst_template"
  yq -i "(.spec.templates[] | select(.name == \"mcp-daemon\") | .container.command) = [\"node\", \"build/index.js\"]" \
    "$dst_template"
  # mock-api가 사용할 LINEAR_API_URL을 자기 자신으로 지정 (MCP 서버가 mock-api를 바라봄)
  yq -i "(.spec.templates[] | select(.name == \"agent-job\") | .container.env[] | select(.name == \"MCP_HOST\") | .value) = \"localhost\"" \
    "$dst_template" 2>/dev/null || true

  # llm-gateway-daemon은 nginx로 유지하되, 실제 Anthropic API 대신 mock-api를 바라보도록
  # 설정 변경은 ConfigMap 레벨에서 수행되므로 여기서는 이미지를 그대로 둡니다.
  # (Level 2에서는 LLM 응답도 mock-agent가 직접 처리하므로 llm-gateway 불필요)
  # llm-gateway-daemon을 busybox sleep으로 교체하여 데몬 자리만 차지합니다.
  yq -i "(.spec.templates[] | select(.name == \"llm-gateway-daemon\") | .container.image) = \"busybox:1.36\"" \
    "$dst_template"
  yq -i "(.spec.templates[] | select(.name == \"llm-gateway-daemon\") | .container.command) = [\"sh\", \"-c\", \"while true; do sleep 3600; done\"]" \
    "$dst_template"
  # livenessProbe 제거 (busybox에는 nginx liveness가 불필요)
  yq -i 'del(.spec.templates[] | select(.name == "llm-gateway-daemon") | .container.livenessProbe)' \
    "$dst_template"

  log "WorkflowTemplate patched: $dst_template"
}

# apply_mock_workflow_template: 패치된 WorkflowTemplate을 클러스터에 적용합니다.
apply_mock_workflow_template() {
  local dst_template="$1"

  log "Applying mock WorkflowTemplate to cluster (context=$KUBE_CONTEXT, ns=$NAMESPACE)"
  kubectl --context "$KUBE_CONTEXT" \
    apply -n "$NAMESPACE" -f "$dst_template"
}

# submit_mock_workflow: Level ②용 Argo Workflow를 제출합니다.
# mock-agent는 SCENARIO_DIR ConfigMap에서 fixture를 읽어야 하므로
# 시나리오 사이클 fixture를 ConfigMap으로 먼저 생성합니다.
#
# 출력: workflow name
submit_mock_workflow() {
  local scenario_name="$1"
  local scenario_yaml="$2"
  local cycle_index="${3:-0}"

  local cm_name="mock-scenario-${scenario_name}-cycle${cycle_index}"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  # ── fixture 추출 ──────────────────────────────────────────────────────────
  local export_config agent_result
  export_config=$(yq eval ".cycles[${cycle_index}].export_config" "$scenario_yaml")
  agent_result=$(yq  eval ".cycles[${cycle_index}].agent_result // \"\"" "$scenario_yaml")

  if [[ "$export_config" != "null" && -n "$export_config" ]]; then
    echo "$export_config" | yq -o=json > "${tmp_dir}/export_config.json"
  fi
  if [[ -n "$agent_result" ]]; then
    echo "$agent_result" > "${tmp_dir}/agent_result.txt"
  fi

  # ── fixture를 ConfigMap으로 생성 ──────────────────────────────────────────
  local kubectl_args=()
  kubectl_args+=(--context "$KUBE_CONTEXT" -n "$NAMESPACE")
  kubectl_args+=(create configmap "$cm_name")

  if [[ -f "${tmp_dir}/export_config.json" ]]; then
    kubectl_args+=(--from-file="export_config.json=${tmp_dir}/export_config.json")
  fi
  if [[ -f "${tmp_dir}/agent_result.txt" ]]; then
    kubectl_args+=(--from-file="agent_result.txt=${tmp_dir}/agent_result.txt")
  fi
  kubectl_args+=(--dry-run=client -o yaml)

  kubectl "${kubectl_args[@]}" | kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" apply -f -

  rm -rf "$tmp_dir"

  # ── max_depth 결정 ────────────────────────────────────────────────────────
  local max_depth
  max_depth=$(yaml_get "$scenario_yaml" '.max_depth // 5')

  # ── Workflow 제출 (SCENARIO_DIR を ConfigMap マウントとして渡す) ────────────
  log "Submitting Level 2 mock workflow for scenario: $scenario_name (cycle=$cycle_index)"

  local submit_output
  submit_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="mock-prompt-${scenario_name}" \
    --labels "e2e-level=2,e2e-scenario=${scenario_name}" \
    --output json 2>&1) || {
      warn "Argo workflow submission failed:"
      echo "$submit_output" >&2
      die "Workflow submission failed for scenario: $scenario_name"
    }

  local workflow_name
  workflow_name=$(echo "$submit_output" | jq -r '.metadata.name')
  log "Submitted Level 2 workflow: $workflow_name"
  echo "$workflow_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# build_prompt: 시나리오 YAML의 real.prompt를 읽고 변수를 치환합니다.
build_prompt() {
  local yaml_file="$1"
  local linear_issue_id="${2:-}"
  local github_branch="${3:-}"

  local prompt
  prompt=$(yaml_get "$yaml_file" '.real.prompt')
  [[ -n "$prompt" ]] \
    || die "Prompt not defined in: $yaml_file (real.prompt)"

  # 변수 치환
  prompt="${prompt//\{\{LINEAR_ISSUE_ID\}\}/$linear_issue_id}"
  prompt="${prompt//\{\{GITHUB_TEST_REPO\}\}/$GITHUB_TEST_REPO}"
  prompt="${prompt//\{\{GITHUB_BRANCH\}\}/$github_branch}"

  echo "$prompt"
}

# run_argo_workflow: Argo Workflow를 제출하고 완료까지 대기합니다.
# 출력: workflow name (예: "pure-agent-abcde")
run_argo_workflow() {
  local scenario_name="$1"
  local prompt="$2"
  local max_depth="${3:-5}"

  log "Submitting Argo Workflow for scenario: $scenario_name"
  log "Prompt: $prompt"

  local submit_output
  submit_output=$(argo submit \
    --from workflowtemplate/pure-agent \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    -p max_depth="$max_depth" \
    -p prompt="$prompt" \
    --output json 2>&1) || {
      warn "Argo workflow submission failed:"
      echo "$submit_output" >&2
      die "Workflow failed for scenario: $scenario_name"
    }

  local workflow_name
  workflow_name=$(echo "$submit_output" | jq -r '.metadata.name')
  log "Submitted workflow: $workflow_name — waiting up to ${WORKFLOW_TIMEOUT}s"

  local wait_exit=0
  timeout "${WORKFLOW_TIMEOUT}s" \
    argo wait "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" || wait_exit=$?

  # Always fetch workflow status for diagnostics
  local workflow_output
  workflow_output=$(argo get "$workflow_name" \
    -n "$NAMESPACE" \
    --context "$KUBE_CONTEXT" \
    --output json 2>&1) || true

  local workflow_phase
  workflow_phase=$(echo "$workflow_output" | jq -r '.status.phase // "Unknown"')

  if [[ "$wait_exit" -ne 0 ]]; then
    if [[ "$wait_exit" -eq 124 ]]; then
      warn "Workflow timed out after ${WORKFLOW_TIMEOUT}s: $workflow_name (phase=$workflow_phase)"
    else
      warn "argo wait failed (exit=$wait_exit) for: $workflow_name (phase=$workflow_phase)"
    fi
    # Dump workflow node tree for debugging
    log "=== Workflow status ==="
    argo get "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" 2>&1 >&2 || true
    log "=== Pod status ==="
    kubectl get pods \
      -l "workflows.argoproj.io/workflow=$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" \
      -o wide 2>&1 >&2 || true
    log "=== Workflow logs (last 200 lines) ==="
    argo logs "$workflow_name" \
      -n "$NAMESPACE" \
      --context "$KUBE_CONTEXT" 2>&1 | tail -200 >&2 || true
    log "=== End diagnostics ==="
    die "Workflow failed for scenario: $scenario_name"
  fi

  log "Workflow completed: name=$workflow_name phase=$workflow_phase"

  [[ "$workflow_phase" == "Succeeded" ]] \
    || die "Workflow did not succeed (phase=$workflow_phase) for scenario: $scenario_name"

  echo "$workflow_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GENERIC SCENARIO RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

# discover_scenarios: 현재 LEVEL을 지원하는 시나리오 YAML 파일 목록을 반환합니다.
discover_scenarios() {
  local yaml_file
  for yaml_file in "$SCENARIOS_DIR"/*.yaml; do
    [[ -f "$yaml_file" ]] || continue
    # level 배열에 현재 LEVEL이 포함된 시나리오만 대상
    local has_level
    has_level=$(yq eval ".level[] | select(. == ${LEVEL})" "$yaml_file" 2>/dev/null || true)
    [[ -n "$has_level" ]] || continue
    yaml_get "$yaml_file" '.name'
  done
}

# run_scenario: YAML 정의를 읽고 setup → run → verify → teardown을 수행합니다.
# Level ② / Level ③ 분기는 LEVEL 변수로 결정됩니다.
run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== Scenario: $scenario_name (Level ${LEVEL}) ==="

  if [[ "${LEVEL}" -eq 2 ]]; then
    run_scenario_level2 "$scenario_name" "$yaml_file"
  else
    run_scenario_level3 "$scenario_name" "$yaml_file"
  fi
}

# run_scenario_level2: Level ② シナリオを mock-agent + mock-api で実行します。
#
# Level ② では実際の API / Claude Agent を使わず、
# WorkflowTemplate を mock イメージで上書きして Argo レイヤーを検証します。
run_scenario_level2() {
  local scenario_name="$1"
  local yaml_file="$2"

  # ── WorkflowTemplate を mock イメージでパッチして適用 ─────────────────────
  local src_template="${SCRIPT_DIR}/../k8s/workflow-template.yaml"
  local dst_template="/tmp/workflow-template-level2-${scenario_name}.yaml"

  patch_workflow_template_for_mock "$src_template" "$dst_template" "$scenario_name"
  apply_mock_workflow_template "$dst_template"

  # ── サイクル数を YAML から取得 ────────────────────────────────────────────
  local cycle_count
  cycle_count=$(yq eval '.cycles | length' "$yaml_file" 2>/dev/null || echo "1")

  local last_workflow_name=""
  local cycle_idx=0

  while [[ "$cycle_idx" -lt "$cycle_count" ]]; do
    log "--- Level 2 cycle ${cycle_idx}/${cycle_count} for scenario: ${scenario_name} ---"

    last_workflow_name=$(submit_mock_workflow "$scenario_name" "$yaml_file" "$cycle_idx")

    # ── Wait for workflow completion ─────────────────────────────────────────
    local wait_exit=0
    timeout "${WORKFLOW_TIMEOUT}s" \
      argo wait "$last_workflow_name" \
        -n "$NAMESPACE" \
        --context "$KUBE_CONTEXT" || wait_exit=$?

    if [[ "$wait_exit" -ne 0 ]]; then
      log "=== Workflow diagnostics for: $last_workflow_name ==="
      argo get "$last_workflow_name" \
        -n "$NAMESPACE" --context "$KUBE_CONTEXT" 2>&1 >&2 || true
      kubectl get pods \
        -l "workflows.argoproj.io/workflow=$last_workflow_name" \
        -n "$NAMESPACE" --context "$KUBE_CONTEXT" -o wide 2>&1 >&2 || true
      argo logs "$last_workflow_name" \
        -n "$NAMESPACE" --context "$KUBE_CONTEXT" 2>&1 | tail -200 >&2 || true
      die "Level 2 workflow timed out or failed: $last_workflow_name"
    fi

    # ── Workflow 상태 확인 ───────────────────────────────────────────────────
    local workflow_phase
    workflow_phase=$(argo get "$last_workflow_name" \
      -n "$NAMESPACE" --context "$KUBE_CONTEXT" --output json \
      | jq -r '.status.phase // "Unknown"')

    log "Workflow phase: $workflow_phase (name=$last_workflow_name)"
    [[ "$workflow_phase" == "Succeeded" ]] \
      || die "Level 2 workflow did not succeed (phase=$workflow_phase): $last_workflow_name"

    cycle_idx=$(( cycle_idx + 1 ))
  done

  log "=== PASS: $scenario_name (Level 2) ==="
}

# run_scenario_level3: Level ③ シナリオ (実際の API) を実行します。
run_scenario_level3() {
  local scenario_name="$1"
  local yaml_file="$2"

  # ── YAML에서 설정 읽기 ──
  local max_depth
  max_depth=$(yaml_get "$yaml_file" '.real.max_depth // 5')

  # setup/teardown/verify 목록 (YAML 배열 → 줄바꿈 구분 문자열)
  local setups teardowns verifies
  setups=$(yaml_get "$yaml_file" '.real.setup[]' 2>/dev/null || true)
  teardowns=$(yaml_get "$yaml_file" '.real.teardown[]' 2>/dev/null || true)
  verifies=$(yaml_get "$yaml_file" '.real.verify[]' 2>/dev/null || true)

  # ── Setup ──
  local linear_issue_id=""
  local github_branch=""

  local setup_item
  while IFS= read -r setup_item; do
    [[ -n "$setup_item" ]] || continue
    case "$setup_item" in
      linear_issue)
        linear_issue_id=$(setup_linear_test_issue "$scenario_name")
        ;;
      github_branch)
        github_branch=$(setup_github_test_branch "$scenario_name")
        ;;
      *) warn "Unknown setup type: $setup_item" ;;
    esac
  done <<< "$setups"

  # ── Teardown trap (cleanup even on failure) ──
  _teardown_handler() {
    local td_item
    while IFS= read -r td_item; do
      [[ -n "$td_item" ]] || continue
      case "$td_item" in
        linear_issue)  teardown_linear_issue "$linear_issue_id" ;;
        github_branch) teardown_github_pr_and_branch "$github_branch" ;;
        *) warn "Unknown teardown type: $td_item" ;;
      esac
    done <<< "$1"
  }
  # shellcheck disable=SC2064
  trap "_teardown_handler '$teardowns'" EXIT

  # ── Run ──
  local prompt
  prompt=$(build_prompt "$yaml_file" "$linear_issue_id" "$github_branch")
  run_argo_workflow "$scenario_name" "$prompt" "$max_depth"

  # ── Verify (assertions) ──
  local verify_item
  while IFS= read -r verify_item; do
    [[ -n "$verify_item" ]] || continue
    case "$verify_item" in
      linear_comment)
        local body_contains
        body_contains=$(yaml_get "$yaml_file" '.assertions.linear_comment.body_contains')
        verify_linear_comment "$linear_issue_id" "$body_contains"
        ;;
      github_pr)
        verify_github_pr "$github_branch"
        ;;
      *) warn "Unknown verify type: $verify_item" ;;
    esac
  done <<< "$verifies"

  # ── Teardown (explicit, then clear trap) ──
  _teardown_handler "$teardowns"
  trap - EXIT

  log "=== PASS: $scenario_name ==="
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log "Starting Level ${LEVEL} E2E test runner"
  log "SCENARIO=${SCENARIO}, LEVEL=${LEVEL}, NAMESPACE=${NAMESPACE}"

  check_prerequisites

  if [[ "$SCENARIO" == "all" ]]; then
    local scenarios
    scenarios=$(discover_scenarios)
    [[ -n "$scenarios" ]] \
      || die "No scenarios for level ${LEVEL} found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All scenarios completed"
}

main "$@"
