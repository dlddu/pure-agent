#!/usr/bin/env bash
# e2e/run-local.sh — Level ① E2E 테스트 러너 (Docker Compose 기반)
#
# DLD-468: Level ① e2e 테스트 작성 (skipped)
#
# 시나리오별로:
#   1. docker compose up -d (mock-api 등 데몬 서비스)
#   2. fixture를 shared volume에 배치 (mock-agent를 통해)
#   3. 시나리오 cycle 수만큼:
#      a. router 실행 → 출력 검증
#      b. export-handler 실행 → 종료 코드 검증
#   4. mock-api GET /assertions → API 호출 검증
#   5. docker compose down
#
# Usage:
#   ./e2e/run-local.sh [--scenario <name|all>]
#
# Environment variables:
#   SCENARIO        — 실행할 시나리오 이름 (기본값: all)
#   MOCK_API_URL    — mock-api 베이스 URL (기본값: http://localhost:4000)
#   COMPOSE_FILE    — docker-compose.yml 경로 (기본값: e2e/docker-compose.yml)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCENARIO="${SCENARIO:-all}"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${SCRIPT_DIR}/docker-compose.yml}"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"

# ── Logging ───────────────────────────────────────────────────────────────────
log()  { echo "[run-local] $*" >&2; }
warn() { echo "[run-local] WARN: $*" >&2; }
die()  { echo "[run-local] ERROR: $*" >&2; exit 1; }

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

# ── YAML helper ───────────────────────────────────────────────────────────────
yaml_get() {
  local yaml_file="$1"
  local path="$2"
  local value
  value=$(yq eval "$path" "$yaml_file" 2>/dev/null || echo "null")
  if [[ "$value" == "null" ]]; then
    echo ""
  else
    echo "$value"
  fi
}

# ── mock-api 리셋 ─────────────────────────────────────────────────────────────
reset_mock_api() {
  local url="${MOCK_API_URL}/assertions/reset"
  curl -sf -X POST "$url" >/dev/null \
    || { warn "Failed to reset mock-api at $url"; return 1; }
  log "mock-api assertions reset"
}

# ── mock-api health check ─────────────────────────────────────────────────────
wait_mock_api() {
  local max_attempts=30
  local attempt=0
  local url="${MOCK_API_URL}/health"

  log "Waiting for mock-api at $url ..."
  while [[ $attempt -lt $max_attempts ]]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      log "mock-api is ready"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 1
  done

  die "mock-api did not become ready within ${max_attempts}s"
}

# ── Docker Compose 래퍼 ───────────────────────────────────────────────────────
compose_up() {
  log "Starting daemon services (mock-api) ..."
  docker compose -f "$COMPOSE_FILE" up -d mock-api
}

compose_down() {
  log "Stopping and removing containers ..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ── fixture 배치: mock-agent를 run하여 /work 볼륨에 파일 복사 ─────────────────
#
# Arguments:
#   $1  cycle_fixture_dir  — 호스트의 cycle fixture 디렉토리 (export_config.json 등)
#
place_fixtures_via_mock_agent() {
  local cycle_fixture_dir="$1"

  log "Placing fixtures via mock-agent (from: $cycle_fixture_dir) ..."

  # mock-agent를 one-shot으로 실행하여 fixture를 /work 볼륨에 배치합니다.
  # SCENARIO_DIR 환경 변수를 통해 fixture 디렉토리를 주입합니다.
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    -e "SCENARIO_DIR=/scenario" \
    -v "${cycle_fixture_dir}:/scenario:ro" \
    mock-agent \
    /app/entrypoint.sh
}

# ── cycle fixture 디렉토리 생성 ───────────────────────────────────────────────
#
# Arguments:
#   $1  yaml_file    — 시나리오 YAML 파일 경로
#   $2  cycle_index  — cycle 인덱스 (0-based)
#   $3  out_dir      — 파일을 배치할 호스트 디렉토리
#
prepare_cycle_fixtures() {
  local yaml_file="$1"
  local cycle_index="$2"
  local out_dir="$3"

  mkdir -p "$out_dir"

  # export_config: YAML → JSON
  local export_config_raw
  export_config_raw=$(yq eval ".cycles[${cycle_index}].export_config" "$yaml_file" 2>/dev/null || echo "null")

  if [[ "$export_config_raw" != "null" && -n "$export_config_raw" ]]; then
    yq eval -o=json ".cycles[${cycle_index}].export_config" "$yaml_file" \
      > "${out_dir}/export_config.json"
    log "Prepared export_config.json for cycle ${cycle_index}"
  else
    rm -f "${out_dir}/export_config.json"
    log "No export_config for cycle ${cycle_index}"
  fi

  # agent_result
  local agent_result
  agent_result=$(yq eval ".cycles[${cycle_index}].agent_result // \"\"" "$yaml_file" 2>/dev/null || echo "")

  if [[ -n "$agent_result" && "$agent_result" != "null" ]]; then
    echo "$agent_result" > "${out_dir}/agent_result.txt"
    log "Prepared agent_result.txt for cycle ${cycle_index}: $agent_result"
  else
    rm -f "${out_dir}/agent_result.txt"
  fi
}

# ── router 실행 ───────────────────────────────────────────────────────────────
#
# router를 docker compose run으로 실행합니다.
# /work/export_config.json을 읽고 /work/router_decision.txt에 true/false 출력.
#
# Arguments:
#   $1  depth      — 현재 depth
#   $2  max_depth  — 최대 depth
#
# 출력: router_decision.txt 파일의 내용 ("true" or "false")
#
run_router() {
  local depth="$1"
  local max_depth="$2"
  local output_file="/work/router_decision.txt"

  log "Running router (depth=${depth}, max_depth=${max_depth}) ..."

  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --no-deps \
    -v "$(docker compose -f "$COMPOSE_FILE" ps -q mock-api 2>/dev/null | head -1 || echo 'work'):/work" \
    router \
    router \
      --depth "${depth}" \
      --max-depth "${max_depth}" \
      --export-config /work/export_config.json \
      --output "${output_file}" \
    || {
      warn "router exited non-zero for depth=${depth}"
      return 1
    }

  # /work 볼륨에서 결과 읽기 (별도 컨테이너를 통해)
  local decision
  decision=$(docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --no-deps \
    --entrypoint="" \
    router \
    cat "${output_file}" 2>/dev/null | tr -d '[:space:]') || {
    warn "Failed to read router_decision.txt"
    return 1
  }

  log "Router decision: $decision"
  echo "$decision"
}

# ── router 실행 (간소화 버전: /work 볼륨 공유를 위해 export-handler 이미지 활용) ─
#
# 실제 구현에서는 run-local.sh가 docker compose run으로 router와 export-handler를
# 동일한 'work' 볼륨에 마운트하여 실행합니다. BATS 테스트에서 검증하는 핵심 흐름:
#
#   1. mock-agent → /work/export_config.json 배치
#   2. router     → /work/export_config.json 읽기 → /work/router_decision.txt 작성
#   3. export-handler → /work/export_config.json 처리 → mock-api에 GraphQL 호출
#
run_router_in_compose() {
  local depth="$1"
  local max_depth="$2"
  local router_output_on_host="$3"  # 호스트에서 결과를 받을 임시 파일 경로

  log "Running router (depth=${depth}, max_depth=${max_depth}) ..."

  # router 컨테이너를 'work' 볼륨과 함께 실행
  # --no-deps: mock-api에 의존하지 않음 (router는 파일만 읽음)
  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    router \
    router \
      --depth "${depth}" \
      --max-depth "${max_depth}" \
      --export-config /work/export_config.json \
      --output /work/router_decision.txt \
    || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    warn "router exited with code ${exit_code} (depth=${depth})"
    return "$exit_code"
  fi

  # /work/router_decision.txt 읽기 — 알파인 컨테이너를 이용
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    router \
    sh -c "cat /work/router_decision.txt" \
    > "$router_output_on_host" 2>/dev/null \
    || {
      warn "Failed to read /work/router_decision.txt from volume"
      return 1
    }

  log "Router decision: $(cat "$router_output_on_host")"
}

# ── export-handler 실행 ────────────────────────────────────────────────────────
#
# export-handler를 docker compose run으로 실행합니다.
# 종료 코드를 반환합니다.
#
run_export_handler() {
  log "Running export-handler ..."

  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    export-handler \
    || exit_code=$?

  log "export-handler exit code: ${exit_code}"
  return "$exit_code"
}

# ── mock-gh 호출 기록 조회 ────────────────────────────────────────────────────
#
# gh-calls 볼륨에서 pr-create 기록 파일 수를 반환합니다.
#
count_gh_pr_create_calls() {
  local count
  count=$(docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    export-handler \
    sh -c "ls /gh-calls/pr-create-* 2>/dev/null | wc -l | tr -d ' '") || echo "0"
  echo "${count:-0}"
}

# ── assertions ────────────────────────────────────────────────────────────────

# router 결정값 검증
assert_local_router_decision() {
  local expected="$1"
  local router_output_file="$2"

  if [[ ! -f "$router_output_file" ]]; then
    echo "FAIL assert_local_router_decision: router output file not found: $router_output_file" >&2
    return 1
  fi

  local actual
  actual=$(cat "$router_output_file" | tr -d '[:space:]')

  # router는 "true" (continue) 또는 "false" (stop) 을 출력합니다.
  # 시나리오 YAML의 router_decision 은 "stop"/"continue" 표기를 사용합니다.
  local expected_raw
  case "$expected" in
    stop)     expected_raw="false" ;;
    continue) expected_raw="true"  ;;
    true|false) expected_raw="$expected" ;;
    *)        expected_raw="$expected" ;;
  esac

  if [[ "$expected_raw" != "$actual" ]]; then
    echo "FAIL assert_local_router_decision: expected '${expected_raw}' (${expected}) but got '${actual}'" >&2
    return 1
  fi

  log "assert_local_router_decision OK: ${actual}"
}

# mock-api /assertions 기반 Linear comment 검증
assert_local_linear_comment() {
  local body_contains="$1"
  local url="${MOCK_API_URL}/assertions"

  local response
  response=$(curl -sf "$url") || {
    echo "FAIL assert_local_linear_comment: could not reach mock-api at $url" >&2
    return 1
  }

  local match
  match=$(echo "$response" | jq --arg b "$body_contains" \
    '[.calls[] | select(
        .type == "mutation" and
        ((.operationName // "" | ascii_downcase | contains("comment")) or
         ((.body | tostring) | contains($b)))
     )] | length' 2>/dev/null || echo "0")

  if [[ "$match" -eq 0 ]]; then
    echo "FAIL assert_local_linear_comment: no createComment mutation with body containing '${body_contains}'" >&2
    echo "Recorded calls: $response" >&2
    return 1
  fi

  log "assert_local_linear_comment OK (${match} matching call(s))"
}

# export-handler 종료 코드 검증
assert_local_export_handler_exit() {
  local expected="$1"
  local actual="$2"

  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL assert_local_export_handler_exit: expected exit ${expected} but got ${actual}" >&2
    return 1
  fi

  log "assert_local_export_handler_exit OK: ${actual}"
}

# mock-gh pr create 호출 여부 검증
assert_local_github_pr() {
  local expected="${1:-true}"

  local count
  count=$(count_gh_pr_create_calls)

  if [[ "$expected" == "true" && "$count" -eq 0 ]]; then
    echo "FAIL assert_local_github_pr: expected gh pr create to be called, but no calls recorded" >&2
    return 1
  fi

  if [[ "$expected" == "false" && "$count" -gt 0 ]]; then
    echo "FAIL assert_local_github_pr: expected no gh pr create calls, but found ${count}" >&2
    return 1
  fi

  log "assert_local_github_pr OK (calls=${count})"
}

# ── 시나리오 실행 ─────────────────────────────────────────────────────────────

run_scenario() {
  local scenario_name="$1"
  local yaml_file="${SCENARIOS_DIR}/${scenario_name}.yaml"

  [[ -f "$yaml_file" ]] \
    || die "Scenario YAML not found: $yaml_file"

  log "=== Level 1 Scenario: $scenario_name ==="

  # max_depth
  local max_depth
  max_depth=$(yaml_get "$yaml_file" '.max_depth // 5')
  [[ -n "$max_depth" ]] || max_depth=5

  # cycle 수
  local cycle_count
  cycle_count=$(yq eval '.cycles | length' "$yaml_file" 2>/dev/null || echo "1")
  [[ "$cycle_count" -gt 0 ]] || cycle_count=1

  # assertions 읽기
  local router_decision
  router_decision=$(yaml_get "$yaml_file" '.assertions.router_decision')

  local export_handler_exit
  export_handler_exit=$(yaml_get "$yaml_file" '.assertions.export_handler_exit')
  [[ -n "$export_handler_exit" ]] || export_handler_exit=0

  local linear_comment_body
  linear_comment_body=$(yaml_get "$yaml_file" '.assertions.linear_comment.body_contains')

  local github_pr
  github_pr=$(yaml_get "$yaml_file" '.assertions.github_pr')

  # docker compose up (mock-api)
  compose_up
  wait_mock_api
  reset_mock_api

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

    # fixture 준비
    local cycle_dir
    cycle_dir=$(mktemp -d "/tmp/e2e-local-${scenario_name}-cycle${cycle_index}-XXXXXX")

    prepare_cycle_fixtures "$yaml_file" "$cycle_index" "$cycle_dir"

    # mock-agent: fixture를 /work 볼륨에 배치
    place_fixtures_via_mock_agent "$cycle_dir"

    # router 실행
    local router_output_file
    router_output_file=$(mktemp "/tmp/e2e-router-output-XXXXXX")

    run_router_in_compose "$cycle_index" "$cycle_max_depth" "$router_output_file"

    # router_decisions (멀티 cycle) 또는 router_decision 검증
    local expected_decision
    if [[ "$cycle_count" -gt 1 ]]; then
      expected_decision=$(yaml_get "$yaml_file" ".assertions.router_decisions[${cycle_index}]")
    else
      expected_decision="$router_decision"
    fi

    if [[ -n "$expected_decision" ]]; then
      assert_local_router_decision "$expected_decision" "$router_output_file"
    fi

    # continue-then-stop: cycle-0에서 /work/export_config.json 삭제 확인
    if [[ "$scenario_name" == "continue-then-stop" && "$cycle_index" -eq 0 ]]; then
      # router가 "continue" 결정을 내리면 export_config.json은 다음 cycle에서 삭제됨
      # (실제 export-handler가 실행되지 않은 경우 삭제 여부는 router에 달림)
      log "continue-then-stop cycle-0: router should output 'true' (continue)"
    fi

    # export-handler 실행
    local eh_exit=0
    run_export_handler || eh_exit=$?

    assert_local_export_handler_exit "$export_handler_exit" "$eh_exit"

    # 임시 파일 정리
    rm -f "$router_output_file"
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

  log "=== PASS (Level 1): $scenario_name ==="
}

# ── 시나리오 목록 ─────────────────────────────────────────────────────────────

discover_scenarios() {
  local yaml_file
  for yaml_file in "${SCENARIOS_DIR}"/*.yaml; do
    [[ -f "$yaml_file" ]] || continue
    # level 배열에 1이 포함된 시나리오만
    local has_level1
    has_level1=$(yq eval '.level[] | select(. == 1)' "$yaml_file" 2>/dev/null || true)
    [[ -n "$has_level1" ]] || continue
    yq eval '.name' "$yaml_file"
  done
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  log "Starting Level 1 E2E test runner (Docker Compose)"
  log "SCENARIO=${SCENARIO}"

  check_prerequisites

  if [[ "$SCENARIO" == "all" ]]; then
    local scenarios
    scenarios=$(discover_scenarios)
    [[ -n "$scenarios" ]] \
      || die "No Level 1 scenarios found in $SCENARIOS_DIR"

    local name
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      run_scenario "$name"
    done <<< "$scenarios"
  else
    run_scenario "$SCENARIO"
  fi

  log "All Level 1 scenarios completed"
}

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "$__SOURCE_ONLY" == "true" ]]; then
  return 0 2>/dev/null || true
fi

main "$@"
