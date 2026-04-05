#!/usr/bin/env bash
# e2e/run-unit.sh — Unit E2E 테스트 러너 (Docker Compose 기반)
#
# Mock:
#   - Agent        → mock-agent (fixture를 /work에 복사)
#   - Linear API   → mock-api (GraphQL mock 서버)
#   - GitHub CLI   → mock-gh (호출 기록만 저장)
#   - Anthropic API → mock-api (Planner의 LLM 호출을 mock 응답으로 대체)
# Real:
#   - Gate         (실제 Python CLI 실행)
#   - Export Handler (실제 TypeScript 실행)
#   - Planner      (실제 Python CLI, LLM 백엔드만 mock)
#   - Gatekeeper   (실제 서비스, DB는 ephemeral)
#
# 시나리오별로:
#   1. docker compose up -d (mock-api 등 데몬 서비스)
#   2. fixture를 shared volume에 배치 (mock-agent를 통해)
#   3. 시나리오 cycle 수만큼:
#      a. gate 실행 → 출력 검증
#      b. export-handler 실행 → 종료 코드 검증
#   4. mock-api GET /assertions → API 호출 검증
#   5. docker compose down
#
# Usage:
#   ./e2e/run-unit.sh [--scenario <name|all>]
#
# Environment variables:
#   SCENARIO        — 실행할 시나리오 이름 (기본값: all)
#   MOCK_API_URL    — mock-api 베이스 URL (기본값: http://localhost:4000)
#   COMPOSE_FILE    — docker-compose.yml 경로 (기본값: e2e/docker-compose.yml)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
LEVEL="${LEVEL:-unit}"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"
GATEKEEPER_URL="${GATEKEEPER_URL:-http://localhost:8080}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${SCRIPT_DIR}/docker-compose.yml}"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"

# ── Logging ───────────────────────────────────────────────────────────────────
log()  { echo "[run-unit] $*" >&2; }
warn() { echo "[run-unit] WARN: $*" >&2; }
die()  { echo "[run-unit] ERROR: $*" >&2; exit 1; }

# ── Source shared libraries ───────────────────────────────────────────────────
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/mock-api.sh
source "${SCRIPT_DIR}/lib/mock-api.sh"
# shellcheck source=lib/mock-gh.sh
source "${SCRIPT_DIR}/lib/mock-gh.sh"
# shellcheck source=lib/compose.sh
source "${SCRIPT_DIR}/lib/compose.sh"
# shellcheck source=lib/assertions-local.sh
source "${SCRIPT_DIR}/lib/assertions-local.sh"
# shellcheck source=lib/gatekeeper.sh
source "${SCRIPT_DIR}/lib/gatekeeper.sh" --source-only

# ── Arg parsing ───────────────────────────────────────────────────────────────
__SOURCE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-only) __SOURCE_ONLY=true; shift ;;
    --scenario)    SCENARIO="$2"; shift 2 ;;
    *)             die "Unknown argument: $1" ;;
  esac
done

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
  command -v docker  >/dev/null 2>&1 || die "docker is not installed"
  docker compose version >/dev/null 2>&1 || die "docker compose plugin is not available"
  command -v curl    >/dev/null 2>&1 || die "curl is not installed"
  command -v jq      >/dev/null 2>&1 || die "jq is not installed"
  command -v yq      >/dev/null 2>&1 || die "yq is not installed"

  [[ -f "$COMPOSE_FILE" ]] \
    || die "docker-compose.yml not found: $COMPOSE_FILE"

  log "Prerequisites OK"
}

# ── 시나리오 실행 ─────────────────────────────────────────────────────────────

run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== Unit Scenario: $scenario_name ==="

  # max_depth
  local max_depth
  max_depth=$(yaml_get "$yaml_file" '.max_depth // 5')
  [[ -n "$max_depth" ]] || max_depth=5

  # cycle 수
  local cycle_count
  cycle_count=$(yq eval '.cycles | length' "$yaml_file" 2>/dev/null || echo "1")
  [[ "$cycle_count" -gt 0 ]] || cycle_count=1

  # assertions 읽기
  local gate_decision
  gate_decision=$(yaml_get "$yaml_file" '.assertions.gate_decision')

  local export_handler_exit
  export_handler_exit=$(yaml_get "$yaml_file" '.assertions.export_handler_exit')
  [[ -n "$export_handler_exit" ]] || export_handler_exit=0

  local linear_comment_body
  linear_comment_body=$(yaml_get "$yaml_file" '.assertions.linear_comment.body_contains')

  local github_pr
  github_pr=$(yaml_get "$yaml_file" '.assertions.github_pr')

  local planner_image
  planner_image=$(yaml_get "$yaml_file" '.assertions.planner_image')

  # docker compose up (mock-api, gatekeeper)
  compose_up
  wait_mock_api
  reset_mock_api
  wait_gatekeeper

  # 정리 trap
  trap 'compose_down' EXIT

  local cycle_index
  for (( cycle_index=0; cycle_index<cycle_count; cycle_index++ )); do
    log "--- Cycle ${cycle_index}/${cycle_count} ---"

    # per-cycle max_depth
    local cycle_max_depth
    cycle_max_depth=$(yaml_get "$yaml_file" ".cycles[${cycle_index}].max_depth")
    if [[ -z "$cycle_max_depth" ]]; then
      cycle_max_depth="$max_depth"
    fi

    # planner: mock LLM 환경 설정 + 실행
    local env_id
    env_id=$(yaml_get "$yaml_file" ".cycles[${cycle_index}].environment_id")
    if [[ -n "$env_id" ]]; then
      configure_mock_llm_environment "$env_id"
    fi

    local planner_output_file
    planner_output_file=$(mktemp "/tmp/e2e-planner-output-XXXXXX")
    run_planner_in_compose "test prompt" "$planner_output_file"

    if [[ -n "$planner_image" ]]; then
      assert_local_planner_image "$planner_image" "$planner_output_file"
    fi
    rm -f "$planner_output_file"

    # fixture 준비
    local cycle_dir
    cycle_dir=$(mktemp -d "/tmp/e2e-local-${scenario_name}-cycle${cycle_index}-XXXXXX")

    prepare_cycle_fixtures "$yaml_file" "$cycle_index" "$cycle_dir"

    # mock-agent: fixture를 /work 볼륨에 배치
    place_fixtures_via_mock_agent "$cycle_dir"

    # gate 실행
    local gate_output_file
    gate_output_file=$(mktemp "/tmp/e2e-gate-output-XXXXXX")

    run_gate_in_compose "$cycle_index" "$cycle_max_depth" "$gate_output_file"

    # gate_decisions (멀티 cycle) 또는 gate_decision 검증
    local expected_decision
    if [[ "$cycle_count" -gt 1 ]]; then
      expected_decision=$(yaml_get "$yaml_file" ".assertions.gate_decisions[${cycle_index}]")
    else
      expected_decision="$gate_decision"
    fi

    if [[ -n "$expected_decision" ]]; then
      assert_local_gate_decision "$expected_decision" "$gate_output_file"
    fi

    # continue-then-stop: cycle-0에서 /work/export_config.json 삭제 확인
    if [[ "$scenario_name" == "continue-then-stop" && "$cycle_index" -eq 0 ]]; then
      log "continue-then-stop cycle-0: gate should output 'true' (continue)"
    fi

    # export-handler 실행
    local eh_exit=0
    run_export_handler || eh_exit=$?

    assert_local_export_handler_exit "$export_handler_exit" "$eh_exit"

    # 임시 파일 정리
    rm -f "$gate_output_file"
    rm -rf "$cycle_dir"
  done

  # mock-api assertions 검증
  if [[ -n "$linear_comment_body" ]]; then
    assert_local_linear_comment "$linear_comment_body"
  fi

  if [[ -n "$github_pr" && "$github_pr" != "null" ]]; then
    assert_local_github_pr "$github_pr"
  fi

  # 정리
  trap - EXIT
  compose_down

  log "=== PASS (Unit): $scenario_name ==="
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  log "Starting Unit E2E test runner (Docker Compose)"
  log "SCENARIO=${SCENARIO}"

  check_prerequisites

  if [[ "$SCENARIO" == "all" ]]; then
    local scenarios
    scenarios=$(discover_scenarios)
    [[ -n "$scenarios" ]] \
      || die "No Unit scenarios found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All Unit scenarios completed"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "$__SOURCE_ONLY" == "true" ]]; then
  return 0 2>/dev/null || true
fi

main "$@"
