#!/usr/bin/env bash
# tests/lib/mock-api.sh — mock-api (Linear GraphQL + LLM mock) 헬퍼 함수
#
# mock-api 서비스에 대한 health check, 리셋, LLM 환경 설정 함수를 제공합니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수를 미리 설정해야 합니다:
#   MOCK_API_URL    — mock-api 베이스 URL (예: http://localhost:4000)
#
# 또한 log(), warn(), die() 함수가 호출 스크립트에서 정의되어 있어야 합니다.
#
# Functions:
#   wait_mock_api
#   reset_mock_api
#   configure_mock_llm_environment <environment_id>

set -euo pipefail

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

# ── mock-api 리셋 ─────────────────────────────────────────────────────────────
reset_mock_api() {
  local url="${MOCK_API_URL}/assertions/reset"
  curl -sf -X POST "$url" >/dev/null \
    || { warn "Failed to reset mock-api at $url"; return 1; }
  log "mock-api assertions reset"
}

# ── mock LLM 환경 설정 ───────────────────────────────────────────────────────
configure_mock_llm_environment() {
  local environment_id="$1"
  curl -sf -X POST "${MOCK_API_URL}/v1/messages/configure" \
    -H "Content-Type: application/json" \
    -d "{\"environment_id\": \"${environment_id}\"}" >/dev/null
  log "Configured mock LLM environment: ${environment_id}"
}
