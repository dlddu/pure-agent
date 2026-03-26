#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/tests/run-local-planner.bats — Level ① Planner E2E 시나리오 테스트 (Docker Compose 기반)
#
# 테스트 구조:
#   - Docker Compose 환경에서 planner CLI를 실행합니다.
#   - mock-api의 /v1/messages 엔드포인트가 Anthropic API를 시뮬레이션합니다.
#   - 각 테스트는 특정 프롬프트에 대해 planner가 올바른 환경을 선택하는지 검증합니다.
#
# 전제 조건:
#   - docker (compose plugin 포함)
#   - curl, jq
#   - e2e/docker-compose.yml
#
# 실행 방법:
#   bats e2e/tests/run-local-planner.bats

# ── 경로 설정 ─────────────────────────────────────────────────────────────────
E2E_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
COMPOSE_FILE="${E2E_DIR}/docker-compose.yml"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"

# ── 공통 setup / teardown ─────────────────────────────────────────────────────

setup() {
  export WORK_DIR="${BATS_TEST_TMPDIR}/work"
  export COMPOSE_FILE
  export MOCK_API_URL
  mkdir -p "$WORK_DIR"

  # compose.sh와 planner.sh 로드
  # shellcheck disable=SC1090
  source "${E2E_DIR}/lib/compose.sh"
  # shellcheck disable=SC1090
  source "${E2E_DIR}/lib/planner.sh" --source-only

  # 로깅 함수 정의
  log()  { echo "[run-local-planner] $*" >&2; }
  warn() { echo "[run-local-planner] WARN: $*" >&2; }
  die()  { echo "[run-local-planner] ERROR: $*" >&2; return 1; }
  export -f log warn die
}

teardown() {
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 1: 일반 코딩 프롬프트 → default 환경 선택
#
# 검증 항목:
#   - planner 종료 코드: 0
#   - 선택된 이미지: claude-agent 포함
#   - raw environment ID: default
#   - mock-api에 LLM 호출 기록 존재
# ═══════════════════════════════════════════════════════════════════════════════

@test "planner: general coding prompt selects default environment" {
  # Arrange
  compose_up
  wait_mock_api
  reset_mock_api

  local image_output="${BATS_TEST_TMPDIR}/planner_image.txt"
  local raw_id_output="${BATS_TEST_TMPDIR}/planner_raw_id.txt"

  # Act
  run_planner_in_compose \
    "Review this Python code and fix the bug in the authentication module" \
    "$image_output" \
    "$raw_id_output"

  # Assert: 선택된 이미지가 claude-agent를 포함할 것
  assert_planner_image "$image_output" "claude-agent"

  # Assert: raw environment ID가 "default"일 것
  assert_planner_raw_id "$raw_id_output" "default"

  # Assert: mock-api에 LLM 호출이 기록되었을 것
  assert_planner_llm_called
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 2: 데이터 분석 프롬프트 → python-analysis 환경 선택
#
# 검증 항목:
#   - planner 종료 코드: 0
#   - 선택된 이미지: python-agent 포함
#   - raw environment ID: python-analysis
# ═══════════════════════════════════════════════════════════════════════════════

@test "planner: data analysis prompt selects python-analysis environment" {
  # Arrange
  compose_up
  wait_mock_api
  reset_mock_api

  local image_output="${BATS_TEST_TMPDIR}/planner_image.txt"
  local raw_id_output="${BATS_TEST_TMPDIR}/planner_raw_id.txt"

  # Act
  run_planner_in_compose \
    "pandas로 CSV 데이터 분석하고 matplotlib으로 visualization 차트를 만들어줘" \
    "$image_output" \
    "$raw_id_output"

  # Assert: 선택된 이미지가 python-agent를 포함할 것
  assert_planner_image "$image_output" "python-agent"

  # Assert: raw environment ID가 "python-analysis"일 것
  assert_planner_raw_id "$raw_id_output" "python-analysis"

  # Assert: mock-api에 LLM 호출이 기록되었을 것
  assert_planner_llm_called
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 3: 인프라 프롬프트 → infra 환경 선택
#
# 검증 항목:
#   - planner 종료 코드: 0
#   - 선택된 이미지: infra-agent 포함
#   - raw environment ID: infra
# ═══════════════════════════════════════════════════════════════════════════════

@test "planner: infrastructure prompt selects infra environment" {
  # Arrange
  compose_up
  wait_mock_api
  reset_mock_api

  local image_output="${BATS_TEST_TMPDIR}/planner_image.txt"
  local raw_id_output="${BATS_TEST_TMPDIR}/planner_raw_id.txt"

  # Act
  run_planner_in_compose \
    "kubectl로 Kubernetes 클러스터에 새 서비스를 deploy 해줘" \
    "$image_output" \
    "$raw_id_output"

  # Assert: 선택된 이미지가 infra-agent를 포함할 것
  assert_planner_image "$image_output" "infra-agent"

  # Assert: raw environment ID가 "infra"일 것
  assert_planner_raw_id "$raw_id_output" "infra"

  # Assert: mock-api에 LLM 호출이 기록되었을 것
  assert_planner_llm_called
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 4: LLM gateway 없이 실행 → default 환경 폴백
#
# 검증 항목:
#   - planner 종료 코드: 0
#   - 선택된 이미지: claude-agent 포함 (default)
#   - mock-api에 LLM 호출 기록 없음 (ANTHROPIC_BASE_URL 미설정)
# ═══════════════════════════════════════════════════════════════════════════════

@test "planner: fallback to default when ANTHROPIC_BASE_URL is empty" {
  # Arrange
  compose_up
  wait_mock_api
  reset_mock_api

  local image_output="${BATS_TEST_TMPDIR}/planner_image.txt"

  # Act: ANTHROPIC_BASE_URL을 비워서 planner 실행
  local exit_code=0
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    -e "ANTHROPIC_BASE_URL=" \
    planner \
    sh -c "planner --prompt 'some task' --output /work/planner_image.txt" \
    || exit_code=$?

  # planner 종료 코드 확인
  [ "$exit_code" -eq 0 ]

  # 결과 가져오기
  docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    planner \
    sh -c "cat /work/planner_image.txt" \
    > "$image_output" 2>/dev/null

  # Assert: default 이미지 (claude-agent) 선택
  assert_planner_image "$image_output" "claude-agent"

  # Assert: LLM 호출이 없어야 함
  assert_planner_llm_not_called
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 5: planner가 raw-id-output 없이도 정상 동작
#
# 검증 항목:
#   - planner 종료 코드: 0
#   - 선택된 이미지 파일만 정상 생성
# ═══════════════════════════════════════════════════════════════════════════════

@test "planner: works without raw-id-output flag" {
  # Arrange
  compose_up
  wait_mock_api
  reset_mock_api

  local image_output="${BATS_TEST_TMPDIR}/planner_image.txt"

  # Act: raw-id-output 없이 실행
  run_planner_in_compose \
    "Review this code" \
    "$image_output"

  # Assert: 이미지 파일이 생성됐을 것
  [ -f "$image_output" ]

  # Assert: 이미지 내용이 비어있지 않을 것
  local content
  content=$(cat "$image_output" | tr -d '[:space:]')
  [ -n "$content" ]

  # Assert: 유효한 이미지 URL일 것
  assert_planner_image "$image_output" "ghcr.io/dlddu/pure-agent/"
}
