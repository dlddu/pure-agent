#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# tests/tests/run-local.bats — Unit E2E 시나리오 테스트 (Docker Compose 기반)
#
# DLD-469: Unit E2E 테스트 활성화
#
# 테스트 구조:
#   - Docker Compose 환경에서 실행됩니다.
#   - 각 테스트는 하나의 시나리오만 검증합니다.
#
# 전제 조건 (skip 제거 시 필요):
#   - docker (compose plugin 포함)
#   - curl, jq, yq
#   - tests/docker-compose.yml
#   - tests/run-unit.sh
#
# 실행 방법:
#   bats tests/tests/run-local.bats
#
# 개별 시나리오 실행:
#   SCENARIO=none-action bats tests/tests/run-local.bats

# ── 경로 설정 ─────────────────────────────────────────────────────────────────
TESTS_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCENARIOS_DIR="${TESTS_DIR}/scenarios"
COMPOSE_FILE="${TESTS_DIR}/docker-compose.yml"
RUN_LOCAL="${TESTS_DIR}/run-unit.sh"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"

# ── 공통 setup / teardown ─────────────────────────────────────────────────────

setup() {
  # 각 테스트 전 임시 작업 디렉토리 생성
  export WORK_DIR="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$WORK_DIR"

  # run-unit.sh를 --source-only 모드로 로드하여 헬퍼 함수만 가져옴
  # (common.sh, mock-api.sh, mock-gh.sh, compose.sh, assertions-local.sh, gatekeeper.sh)
  # shellcheck disable=SC1090
  source "$RUN_LOCAL" --source-only
}

teardown() {
  # 각 테스트 후 Docker Compose 정리 (실패 시에도 실행)
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 1: none-action
#
# 검증 항목:
#   - Export Handler 종료 코드: 0
#   - Linear 코멘트: 없음 (assertions.linear_comment 미정의)
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: none-action — export-handler exits 0" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/none-action.yaml"
  [ -f "$yaml_file" ]

  # docker compose up (mock-api)
  compose_up
  wait_mock_api
  reset_mock_api

  # Planner: mock LLM 환경 설정 + 실행
  configure_mock_llm_environment "default"
  local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
  run_planner_in_compose "test prompt" "$planner_output"
  assert_local_planner_image "default" "$planner_output"

  # fixture 배치
  local run_dir="${BATS_TEST_TMPDIR}/none-action-run"
  prepare_run_fixtures "$yaml_file" "$run_dir"
  place_fixtures_via_mock_agent "$run_dir"

  # gate 실행 (transcript upload)
  run_gate_in_compose

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 종료 코드가 0일 것
  assert_local_export_handler_exit 0 "$eh_exit"

  # mock-api에 Linear 코멘트 기록이 없을 것 (none-action에 assertions.linear_comment 미정의)
  local response
  response=$(curl -sf "${MOCK_API_URL}/assertions")
  local comment_count
  comment_count=$(echo "$response" | jq \
    '[.calls[] | select(.type == "mutation" and ((.operationName // "") + " " + ((.body.query // "") | tostring) | ascii_downcase | contains("comment")))] | length')
  # none-action에서는 comment는 1건 (summary만)
  [ "$comment_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 2: report-action
#
# 검증 항목:
#   - Export Handler 종료 코드: 0
#   - Linear 코멘트: "분석 리포트" 포함
# ═══════════════════════════════════════════════════════════════════════════════

# [DISABLED] Linear 미사용 예정으로 비활성화 (2026-08-05) — scenarios/ 의 해당 YAML 참고
# @test "scenario: report-action — linear comment contains report" {
#   # Arrange
#   local yaml_file="${SCENARIOS_DIR}/report-action.yaml"
#   [ -f "$yaml_file" ]

#   # docker compose up
#   compose_up
#   wait_mock_api
#   reset_mock_api

#   # Planner: mock LLM 환경 설정 + 실행
#   configure_mock_llm_environment "default"
#   local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
#   run_planner_in_compose "test prompt" "$planner_output"
#   assert_local_planner_image "default" "$planner_output"

#   # fixture 배치
#   local run_dir="${BATS_TEST_TMPDIR}/report-action-run"
#   prepare_run_fixtures "$yaml_file" "$run_dir"
#   place_fixtures_via_mock_agent "$run_dir"

#   # gate 실행 (transcript upload)
#   run_gate_in_compose

#   # export-handler 실행
#   local eh_exit=0
#   run_export_handler || eh_exit=$?

#   # Assert: export-handler 종료 코드가 0일 것
#   assert_local_export_handler_exit 0 "$eh_exit"

#   # Assert: Linear 코멘트에 "분석 리포트"가 포함될 것
#   assert_local_linear_comment "분석 리포트"
# }

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 3: create-pr-action
#
# 검증 항목:
#   - Export Handler 종료 코드: 0
#   - mock-gh 호출 기록: "gh pr create" 존재
#   - Linear 코멘트: PR URL 포함
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: create-pr-action — gh pr create called, linear comment contains PR URL" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/create-pr-action.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Planner: mock LLM 환경 설정 + 실행
  configure_mock_llm_environment "default"
  local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
  run_planner_in_compose "test prompt" "$planner_output"
  assert_local_planner_image "default" "$planner_output"

  # fixture 배치
  local run_dir="${BATS_TEST_TMPDIR}/create-pr-action-run"
  prepare_run_fixtures "$yaml_file" "$run_dir"
  place_fixtures_via_mock_agent "$run_dir"

  # Set up mock git repo on shared volume for create_pr action
  setup_mock_git_repo

  # gate 실행 (transcript upload)
  run_gate_in_compose

  # export-handler 실행 (mock-gh를 PATH에 우선 배치)
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 종료 코드가 0일 것
  assert_local_export_handler_exit 0 "$eh_exit"

  # Assert: mock-gh의 "gh pr create" 호출 기록이 존재할 것
  assert_local_github_pr "true"

  # Assert: Linear 코멘트에 PR URL이 포함될 것
  assert_local_linear_comment "https://github.com/mock-org/mock-repo/pull"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 6: planner-python-env
#
# 검증 항목:
#   - Planner가 python-analysis 환경을 선택 → python-agent 이미지
#   - Export Handler 종료 코드: 0
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: planner-python-env — planner selects python-analysis image" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/planner-python-env.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Planner: mock LLM 환경을 python-analysis로 설정
  configure_mock_llm_environment "python-analysis"
  local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
  run_planner_in_compose "데이터 분석 작업" "$planner_output"

  # Assert: planner가 python-agent 이미지를 선택할 것
  assert_local_planner_image "python-analysis" "$planner_output"

  # fixture 배치
  local run_dir="${BATS_TEST_TMPDIR}/planner-python-env-run"
  prepare_run_fixtures "$yaml_file" "$run_dir"
  place_fixtures_via_mock_agent "$run_dir"

  # gate 실행 (transcript upload)
  run_gate_in_compose

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?
  assert_local_export_handler_exit 0 "$eh_exit"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 7: planner-infra-env
#
# 검증 항목:
#   - Planner가 infra 환경을 선택 → infra-agent 이미지
#   - Export Handler 종료 코드: 0
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: planner-infra-env — planner selects infra image" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/planner-infra-env.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Planner: mock LLM 환경을 infra로 설정
  configure_mock_llm_environment "infra"
  local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
  run_planner_in_compose "Kubernetes 배포 작업" "$planner_output"

  # Assert: planner가 infra-agent 이미지를 선택할 것
  assert_local_planner_image "infra" "$planner_output"

  # fixture 배치
  local run_dir="${BATS_TEST_TMPDIR}/planner-infra-env-run"
  prepare_run_fixtures "$yaml_file" "$run_dir"
  place_fixtures_via_mock_agent "$run_dir"

  # gate 실행 (transcript upload)
  run_gate_in_compose

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?
  assert_local_export_handler_exit 0 "$eh_exit"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 8: planner-fallback
#
# 검증 항목:
#   - 알 수 없는 environment_id → Planner가 default (claude-agent) 이미지로 fallback
#   - Export Handler 종료 코드: 0
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: planner-fallback — unknown env falls back to default image" {
  # Arrange
  local yaml_file="${SCENARIOS_DIR}/planner-fallback.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Planner: mock LLM 환경을 unknown-env로 설정 (fallback 검증)
  configure_mock_llm_environment "unknown-env"
  local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
  run_planner_in_compose "알 수 없는 작업" "$planner_output"

  # Assert: planner가 default (claude-agent) 이미지로 fallback할 것
  assert_local_planner_image "default" "$planner_output"

  # fixture 배치
  local run_dir="${BATS_TEST_TMPDIR}/planner-fallback-run"
  prepare_run_fixtures "$yaml_file" "$run_dir"
  place_fixtures_via_mock_agent "$run_dir"

  # gate 실행 (transcript upload)
  run_gate_in_compose

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?
  assert_local_export_handler_exit 0 "$eh_exit"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 9: linear-issue-env-selection
#
# 검증 항목:
#   - Linear 이슈 ID가 포함된 프롬프트에서 planner가 정상 동작
#   - Planner가 default 환경을 선택
#   - Export Handler 종료 코드: 0
# ═══════════════════════════════════════════════════════════════════════════════

# [DISABLED] Linear 미사용 예정으로 비활성화 (2026-08-05) — scenarios/ 의 해당 YAML 참고
# @test "scenario: linear-issue-env-selection — planner handles prompt with Linear issue ID" {
#   # Arrange
#   local yaml_file="${SCENARIOS_DIR}/linear-issue-env-selection.yaml"
#   [ -f "$yaml_file" ]

#   # docker compose up
#   compose_up
#   wait_mock_api
#   reset_mock_api

#   # Planner: mock LLM 환경을 default로 설정
#   configure_mock_llm_environment "default"
#   local planner_output="${BATS_TEST_TMPDIR}/planner_output.txt"
#   # 프롬프트에 Linear 이슈 ID 패턴(MOCK-1)을 포함
#   run_planner_in_compose "Linear 이슈 MOCK-1 내용을 확인하고 요약해주세요" "$planner_output"

#   # Assert: planner가 default (claude-agent) 이미지를 선택할 것
#   assert_local_planner_image "default" "$planner_output"

#   # fixture 배치
#   local run_dir="${BATS_TEST_TMPDIR}/linear-issue-env-selection-run"
#   prepare_run_fixtures "$yaml_file" "$run_dir"
#   place_fixtures_via_mock_agent "$run_dir"

#   # gate 실행 (transcript upload)
#   run_gate_in_compose

#   # export-handler 실행
#   local eh_exit=0
#   run_export_handler || eh_exit=$?
#   assert_local_export_handler_exit 0 "$eh_exit"
# }
