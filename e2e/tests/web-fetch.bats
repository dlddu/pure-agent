#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/tests/web-fetch.bats — Gatekeeper 통합 테스트: web_fetch 승인/거절/만료 시나리오
#
# DLD-780: web_fetch e2e 테스트 (skip 상태)
# DLD-781: skip 제거 후 실제 Gatekeeper 구현과 함께 활성화
#
# 테스트 구조:
#   - Docker Compose 환경에서 실행됩니다 (gatekeeper 서비스 포함).
#   - 각 테스트는 하나의 web_fetch 시나리오만 검증합니다.
#   - mock-agent가 web_fetch 호출 → Gatekeeper 승인 요청 생성
#   - e2e 스크립트가 Gatekeeper API를 통해 승인/거절/만료 처리
#   - web_fetch 폴링 결과를 검증합니다.
#
# 전제 조건 (skip 제거 시 필요):
#   - docker (compose plugin 포함)
#   - curl, jq, yq
#   - e2e/docker-compose.yml (gatekeeper 서비스 정의 포함)
#   - GATEKEEPER_URL 환경 변수 설정
#
# 실행 방법:
#   bats e2e/tests/web-fetch.bats
#
# 개별 테스트 실행:
#   bats e2e/tests/web-fetch.bats --filter "approved"

# ── 경로 설정 ─────────────────────────────────────────────────────────────────
E2E_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCENARIOS_DIR="${E2E_DIR}/scenarios"
COMPOSE_FILE="${E2E_DIR}/docker-compose.yml"
RUN_LOCAL="${E2E_DIR}/run-local.sh"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"
GATEKEEPER_URL="${GATEKEEPER_URL:-http://localhost:8080}"

# ── 공통 setup / teardown ─────────────────────────────────────────────────────

setup() {
  # 각 테스트 전 임시 작업 디렉토리 생성
  export WORK_DIR="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$WORK_DIR"

  # run-local.sh를 --source-only 모드로 로드하여 헬퍼 함수만 가져옴
  # shellcheck disable=SC1090
  source "$RUN_LOCAL" --source-only

  # gatekeeper.sh 헬퍼 함수 로드
  # shellcheck disable=SC1090
  source "${E2E_DIR}/lib/gatekeeper.sh" --source-only
}

teardown() {
  # 각 테스트 후 Docker Compose 정리 (실패 시에도 실행)
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# 테스트 1: web_fetch 승인 → 정상 fetch
#
# 검증 항목:
#   - mock-agent가 web_fetch 호출 → Gatekeeper에 PENDING 요청 생성
#   - e2e 스크립트가 테스트 사용자로 로그인하여 JWT 획득
#   - PATCH /api/requests/:id/approve 호출로 승인 처리
#   - web_fetch 폴링이 승인을 감지하고 HTTP fetch 수행
#   - mock-agent 결과: 정상 응답 (exit 0)
# ═══════════════════════════════════════════════════════════════════════════════

@test "web_fetch: approved — gatekeeper approval triggers successful http fetch" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/web-fetch-approved.yaml"
  [ -f "$yaml_file" ]

  # docker compose up (mock-api + gatekeeper 포함)
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치 (mock-agent가 web_fetch 호출하도록 설정)
  local cycle_dir="${BATS_TEST_TMPDIR}/web-fetch-approved-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # Gatekeeper 테스트 사용자 생성 및 로그인
  gatekeeper_signup "e2e-test-user" "e2e-test-password"
  local jwt_token
  jwt_token=$(gatekeeper_login "e2e-test-user" "e2e-test-password")
  [ -n "$jwt_token" ]

  # mock-agent가 web_fetch를 호출하도록 router 실행
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # Gatekeeper PENDING 요청 조회
  local pending_json
  pending_json=$(gatekeeper_get_pending "$jwt_token")
  local request_id
  request_id=$(echo "$pending_json" | jq -r '.[0].id')
  [ -n "$request_id" ]
  [ "$request_id" != "null" ]

  # 승인 처리: PATCH /api/requests/:id/approve
  gatekeeper_approve "$request_id" "$jwt_token"

  # web_fetch 폴링이 승인을 감지하고 fetch를 완료할 때까지 대기
  # (export-handler가 web_fetch 결과를 처리)
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 정상 종료 (web_fetch 성공)
  [ "$eh_exit" -eq 0 ]

  # Assert: router 결정이 stop
  local decision
  decision=$(cat "$router_output" | tr -d '[:space:]')
  [ "$decision" = "false" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 테스트 2: web_fetch 거절 → 에러 반환
#
# 검증 항목:
#   - mock-agent가 web_fetch 호출 → Gatekeeper에 PENDING 요청 생성
#   - e2e 스크립트가 PATCH /api/requests/:id/reject 호출로 거절 처리
#   - web_fetch 폴링이 거절을 감지하고 에러를 반환
#   - mock-agent 결과: 에러 응답 (비정상 종료 또는 에러 메시지 포함)
# ═══════════════════════════════════════════════════════════════════════════════

@test "web_fetch: rejected — gatekeeper rejection causes web_fetch to return error" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/web-fetch-rejected.yaml"
  [ -f "$yaml_file" ]

  # docker compose up (mock-api + gatekeeper 포함)
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치 (mock-agent가 web_fetch 호출하도록 설정)
  local cycle_dir="${BATS_TEST_TMPDIR}/web-fetch-rejected-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # Gatekeeper 테스트 사용자 생성 및 로그인
  gatekeeper_signup "e2e-test-user" "e2e-test-password"
  local jwt_token
  jwt_token=$(gatekeeper_login "e2e-test-user" "e2e-test-password")
  [ -n "$jwt_token" ]

  # mock-agent가 web_fetch를 호출하도록 router 실행
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # Gatekeeper PENDING 요청 조회
  local pending_json
  pending_json=$(gatekeeper_get_pending "$jwt_token")
  local request_id
  request_id=$(echo "$pending_json" | jq -r '.[0].id')
  [ -n "$request_id" ]
  [ "$request_id" != "null" ]

  # 거절 처리: PATCH /api/requests/:id/reject
  gatekeeper_reject "$request_id" "$jwt_token"

  # web_fetch 폴링이 거절을 감지하고 에러를 반환할 때까지 대기
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: web_fetch 거절로 인한 에러가 mock-agent 출력에 반영됨
  # (export-handler는 web_fetch 에러를 처리하고 정상 종료할 수 있음)
  # 실제 에러 검증 방식은 DLD-781에서 구현에 맞게 조정
  [[ "$output" == *"rejected"* ]] || [[ "$output" == *"error"* ]] || [ "$eh_exit" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 테스트 3: web_fetch 만료 → 에러 반환
#
# 검증 항목:
#   - timeoutSeconds를 매우 짧게 설정 (예: 1초)
#   - mock-agent가 web_fetch 호출 → Gatekeeper에 PENDING 요청 생성
#   - 승인 처리 전에 timeoutSeconds 경과 → 요청 만료
#   - web_fetch 폴링이 만료를 감지하고 에러를 반환
#   - mock-agent 결과: timeout 에러 응답
# ═══════════════════════════════════════════════════════════════════════════════

@test "web_fetch: expired — request timeout causes web_fetch to return error" {
  # Arrange
  # timeoutSeconds를 매우 짧게 설정하여 승인 전에 만료되도록 함
  export WEB_FETCH_TIMEOUT_SECONDS="${WEB_FETCH_TIMEOUT_SECONDS:-1}"

  local yaml_file="${SCENARIOS_DIR}/web-fetch-approved.yaml"
  [ -f "$yaml_file" ]

  # docker compose up (mock-api + gatekeeper 포함)
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치 (짧은 timeout으로 web_fetch 호출)
  local cycle_dir="${BATS_TEST_TMPDIR}/web-fetch-timeout-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # Gatekeeper 테스트 사용자 생성 및 로그인
  gatekeeper_signup "e2e-test-user" "e2e-test-password"
  local jwt_token
  jwt_token=$(gatekeeper_login "e2e-test-user" "e2e-test-password")
  [ -n "$jwt_token" ]

  # mock-agent가 web_fetch를 호출하도록 router 실행
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # 승인 처리 없이 timeoutSeconds 이상 대기하여 요청이 만료되도록 함
  # (WEB_FETCH_TIMEOUT_SECONDS=1 이므로 2초 대기)
  sleep 2

  # export-handler 실행: web_fetch 폴링이 만료를 감지하고 에러 반환
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: web_fetch timeout 에러가 출력에 반영됨
  # 실제 에러 검증 방식은 DLD-781에서 구현에 맞게 조정
  [[ "$output" == *"timeout"* ]] || [[ "$output" == *"expired"* ]] || [ "$eh_exit" -ne 0 ]
}
