#!/usr/bin/env bash
# tests/lib/compose.sh — Docker Compose 인프라 및 컴포넌트 실행 헬퍼 함수 (Unit E2E)
#
# Docker Compose 서비스의 시작/종료 및 각 컴포넌트(planner, gate, export-handler,
# mock-agent) 실행 함수를 제공합니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수를 미리 설정해야 합니다:
#   COMPOSE_FILE    — docker-compose.yml 경로
#
# 또한 log(), warn() 함수가 호출 스크립트에서 정의되어 있어야 합니다.
#
# Functions:
#   compose_up
#   compose_down
#   place_fixtures_via_mock_agent <cycle_fixture_dir>
#   run_planner_in_compose <prompt> <planner_output_on_host>
#   run_gate <depth> <max_depth>
#   run_gate_in_compose <depth> <max_depth> <gate_output_on_host>
#   run_export_handler

set -euo pipefail

# ── Docker Compose 래퍼 ───────────────────────────────────────────────────────
compose_up() {
  log "Starting daemon services (mock-api, gatekeeper) ..."
  docker compose -f "$COMPOSE_FILE" up -d mock-api gatekeeper
}

compose_down() {
  log "Stopping and removing containers ..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ── planner 실행 ─────────────────────────────────────────────────────────────
#
# Arguments:
#   $1  prompt                — planner에 전달할 프롬프트
#   $2  planner_output_on_host — 호스트에서 결과를 받을 임시 파일 경로
#
run_planner_in_compose() {
  local prompt="$1"
  local planner_output_on_host="$2"

  log "Running planner ..."

  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    planner \
    sh -c 'planner --prompt "'"${prompt}"'" --output /work/agent_image.txt --raw-id-output /work/raw_environment_id.txt' \
    || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    warn "planner exited with code ${exit_code}"
    return "$exit_code"
  fi

  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    planner \
    sh -c "cat /work/agent_image.txt" \
    > "$planner_output_on_host" 2>/dev/null

  log "Planner output: $(cat "$planner_output_on_host")"
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

# ── gate 실행 ─────────────────────────────────────────────────────────────────
#
# Arguments:
#   $1  depth      — 현재 depth
#   $2  max_depth  — 최대 depth
#
# 출력: gate_decision.txt 파일의 내용 ("true" or "false")
#
run_gate() {
  local depth="$1"
  local max_depth="$2"
  local output_file="/work/gate_decision.txt"

  log "Running gate (depth=${depth}, max_depth=${max_depth}) ..."

  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --no-deps \
    --entrypoint="" \
    gate \
    sh -c '
      EC="{}";
      if [ -f /work/export_config.json ]; then
        EC=$(cat /work/export_config.json);
      fi;
      exec gate \
        --depth '"${depth}"' \
        --max-depth '"${max_depth}"' \
        --export-config "$EC" \
        --output '"${output_file}"'
    ' \
    || {
      warn "gate exited non-zero for depth=${depth}"
      return 1
    }

  local decision
  decision=$(docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --no-deps \
    --entrypoint="" \
    gate \
    cat "${output_file}" 2>/dev/null | tr -d '[:space:]') || {
    warn "Failed to read gate_decision.txt"
    return 1
  }

  log "Gate decision: $decision"
  echo "$decision"
}

# ── gate 실행 (간소화 버전: /work 볼륨 공유를 위해 export-handler 이미지 활용) ──
#
# Arguments:
#   $1  depth      — 현재 depth
#   $2  max_depth  — 최대 depth
#   $3  gate_output_on_host  — 호스트에서 결과를 받을 임시 파일 경로
#
run_gate_in_compose() {
  local depth="$1"
  local max_depth="$2"
  local gate_output_on_host="$3"

  log "Running gate (depth=${depth}, max_depth=${max_depth}) ..."

  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    gate \
    sh -c '
      EC="{}";
      if [ -f /work/export_config.json ]; then
        EC=$(cat /work/export_config.json);
      fi;
      exec gate \
        --depth '"${depth}"' \
        --max-depth '"${max_depth}"' \
        --export-config "$EC" \
        --output /work/gate_decision.txt
    ' \
    || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    warn "gate exited with code ${exit_code} (depth=${depth})"
    return "$exit_code"
  fi

  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    gate \
    sh -c "cat /work/gate_decision.txt" \
    > "$gate_output_on_host" 2>/dev/null \
    || {
      warn "Failed to read /work/gate_decision.txt from volume"
      return 1
    }

  log "Gate decision: $(cat "$gate_output_on_host")"
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
