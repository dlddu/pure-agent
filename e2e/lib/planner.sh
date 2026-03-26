#!/usr/bin/env bash
# e2e/lib/planner.sh — Planner 전용 헬퍼 및 assertion 함수
#
# planner CLI의 E2E 테스트를 위한 Docker Compose 헬퍼와 assertion 함수입니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수/함수를 미리 설정해야 합니다:
#   COMPOSE_FILE    — docker-compose.yml 경로
#   MOCK_API_URL    — mock-api 베이스 URL
#   log()           — 로깅 함수
#
# Functions:
#   run_planner_in_compose <prompt> <output_file> [raw_id_output_file]
#   assert_planner_image <output_file> <expected_substring>
#   assert_planner_raw_id <raw_id_file> <expected_id>
#   assert_planner_llm_called

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  true
fi

# ── Logging ───────────────────────────────────────────────────────────────────
_planner_log()  { echo "[planner] $*" >&2; }
_planner_fail() { echo "FAIL $*" >&2; return 1; }

# ── run_planner_in_compose ─────────────────────────────────────────────────────
# Docker Compose 내에서 planner를 실행합니다.
#
# Arguments:
#   $1  prompt              — 분석할 task prompt
#   $2  output_on_host      — 호스트에서 image 결과를 받을 파일 경로
#   $3  raw_id_on_host      — (선택) 호스트에서 raw environment ID를 받을 파일 경로
#
run_planner_in_compose() {
  local prompt="$1"
  local output_on_host="$2"
  local raw_id_on_host="${3:-}"

  _planner_log "Running planner (prompt='${prompt:0:50}...') ..."

  local raw_id_flag=""
  if [[ -n "$raw_id_on_host" ]]; then
    raw_id_flag="--raw-id-output /work/planner_raw_id.txt"
  fi

  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    planner \
    sh -c "planner --prompt '${prompt}' --output /work/planner_image.txt ${raw_id_flag}" \
    || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    _planner_log "planner exited with code ${exit_code}"
    return "$exit_code"
  fi

  # Copy output from volume to host
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    planner \
    sh -c "cat /work/planner_image.txt" \
    > "$output_on_host" 2>/dev/null \
    || {
      _planner_log "Failed to read /work/planner_image.txt from volume"
      return 1
    }

  if [[ -n "$raw_id_on_host" ]]; then
    docker compose -f "$COMPOSE_FILE" \
      run --rm \
      --entrypoint="" \
      planner \
      sh -c "cat /work/planner_raw_id.txt" \
      > "$raw_id_on_host" 2>/dev/null \
      || {
        _planner_log "Failed to read /work/planner_raw_id.txt from volume"
        return 1
      }
  fi

  _planner_log "Planner image: $(cat "$output_on_host")"
}

# ── assert_planner_image ───────────────────────────────────────────────────────
# planner가 출력한 image URL에 기대하는 부분 문자열이 포함되어 있는지 검증합니다.
#
# Arguments:
#   $1  output_file         — planner image 출력 파일 경로
#   $2  expected_substring  — image URL에 포함되어야 하는 문자열
#
assert_planner_image() {
  local output_file="$1"
  local expected_substring="$2"

  if [[ ! -f "$output_file" ]]; then
    _planner_fail "assert_planner_image: output file not found: $output_file"
    return 1
  fi

  local actual
  actual=$(cat "$output_file" | tr -d '[:space:]')

  if [[ "$actual" != *"$expected_substring"* ]]; then
    _planner_fail "assert_planner_image: expected image containing '$expected_substring' but got '$actual'"
    return 1
  fi

  _planner_log "assert_planner_image OK: $actual contains '$expected_substring'"
}

# ── assert_planner_raw_id ─────────────────────────────────────────────────────
# planner가 출력한 raw environment ID가 기대값과 일치하는지 검증합니다.
#
# Arguments:
#   $1  raw_id_file  — raw environment ID 출력 파일 경로
#   $2  expected_id  — 기대하는 environment ID
#
assert_planner_raw_id() {
  local raw_id_file="$1"
  local expected_id="$2"

  if [[ ! -f "$raw_id_file" ]]; then
    _planner_fail "assert_planner_raw_id: raw ID file not found: $raw_id_file"
    return 1
  fi

  local actual
  actual=$(cat "$raw_id_file" | tr -d '[:space:]')

  if [[ "$actual" != "$expected_id" ]]; then
    _planner_fail "assert_planner_raw_id: expected '$expected_id' but got '$actual'"
    return 1
  fi

  _planner_log "assert_planner_raw_id OK: $actual"
}

# ── assert_planner_llm_called ─────────────────────────────────────────────────
# mock-api에 LLM 호출(type=llm)이 기록되었는지 검증합니다.
#
assert_planner_llm_called() {
  local base_url="${MOCK_API_URL:-http://localhost:4000}"

  local response
  response=$(curl -sf "${base_url}/assertions") || {
    _planner_fail "assert_planner_llm_called: could not reach mock-api at ${base_url}/assertions"
    return 1
  }

  local match
  match=$(echo "$response" | jq \
    '[.calls[] | select(.type == "llm" and .operationName == "selectEnvironment")] | length' \
    2>/dev/null || echo "0")

  if [[ "$match" -eq 0 ]]; then
    _planner_fail "assert_planner_llm_called: no LLM call recorded in mock-api"
    echo "Recorded calls: $response" >&2
    return 1
  fi

  _planner_log "assert_planner_llm_called OK (${match} LLM call(s))"
}

# ── assert_planner_llm_not_called ─────────────────────────────────────────────
# mock-api에 LLM 호출이 기록되지 않았는지 검증합니다.
#
assert_planner_llm_not_called() {
  local base_url="${MOCK_API_URL:-http://localhost:4000}"

  local response
  response=$(curl -sf "${base_url}/assertions") || {
    _planner_fail "assert_planner_llm_not_called: could not reach mock-api at ${base_url}/assertions"
    return 1
  }

  local match
  match=$(echo "$response" | jq \
    '[.calls[] | select(.type == "llm")] | length' \
    2>/dev/null || echo "0")

  if [[ "$match" -gt 0 ]]; then
    _planner_fail "assert_planner_llm_not_called: expected no LLM calls but found ${match}"
    return 1
  fi

  _planner_log "assert_planner_llm_not_called OK"
}
