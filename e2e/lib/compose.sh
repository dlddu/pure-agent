#!/usr/bin/env bash
# e2e/lib/compose.sh — Docker Compose 헬퍼 함수 (Level ① E2E)
#
# run-local.sh에서 추출된 Docker Compose 관련 함수들입니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수를 미리 설정해야 합니다:
#   COMPOSE_FILE    — docker-compose.yml 경로
#   MOCK_API_URL    — mock-api 베이스 URL
#
# 또한 log(), warn() 함수가 호출 스크립트에서 정의되어 있어야 합니다.
#
# Functions:
#   compose_up
#   compose_down
#   wait_mock_api
#   reset_mock_api
#   place_fixtures_via_mock_agent <cycle_fixture_dir>
#   run_router <depth> <max_depth>
#   run_router_in_compose <depth> <max_depth> <router_output_on_host>
#   run_export_handler
#   count_gh_pr_create_calls

set -euo pipefail

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || true
fi

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

  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    -e "SCENARIO_DIR=/scenario" \
    -v "${cycle_fixture_dir}:/scenario:ro" \
    mock-agent \
    /app/entrypoint.sh
}

# ── router 실행 ───────────────────────────────────────────────────────────────
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
    --entrypoint="" \
    router \
    sh -c '
      EC="{}";
      if [ -f /work/export_config.json ]; then
        EC=$(cat /work/export_config.json);
      fi;
      exec router \
        --depth '"${depth}"' \
        --max-depth '"${max_depth}"' \
        --export-config "$EC" \
        --output '"${output_file}"'
    ' \
    || {
      warn "router exited non-zero for depth=${depth}"
      return 1
    }

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
# Arguments:
#   $1  depth      — 현재 depth
#   $2  max_depth  — 최대 depth
#   $3  router_output_on_host  — 호스트에서 결과를 받을 임시 파일 경로
#
run_router_in_compose() {
  local depth="$1"
  local max_depth="$2"
  local router_output_on_host="$3"

  log "Running router (depth=${depth}, max_depth=${max_depth}) ..."

  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    router \
    sh -c '
      EC="{}";
      if [ -f /work/export_config.json ]; then
        EC=$(cat /work/export_config.json);
      fi;
      exec router \
        --depth '"${depth}"' \
        --max-depth '"${max_depth}"' \
        --export-config "$EC" \
        --output /work/router_decision.txt
    ' \
    || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    warn "router exited with code ${exit_code} (depth=${depth})"
    return "$exit_code"
  fi

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
count_gh_pr_create_calls() {
  local count
  count=$(docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    export-handler \
    sh -c "ls /gh-calls/pr-create-* 2>/dev/null | wc -l | tr -d ' '") || echo "0"
  echo "${count:-0}"
}
