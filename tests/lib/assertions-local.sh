#!/usr/bin/env bash
# tests/lib/assertions-local.sh — Unit (Docker Compose) 전용 assertion helpers
#
# run-unit.sh에서 추출된 로컬 환경 전용 assertion 함수들입니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수/함수를 미리 설정해야 합니다:
#   MOCK_API_URL    — mock-api 베이스 URL
#   log()           — 로깅 함수
#   count_gh_pr_create_calls()  — lib/compose.sh에서 제공
#
# Functions:
#   assert_local_export_handler_exit <expected> <actual>
#   assert_local_github_pr [expected]

set -euo pipefail

# ── assert_local_planner_image ───────────────────────────────────────────────
# planner가 선택한 이미지 검증
#
# Arguments:
#   $1  expected_env_id       — 기대하는 environment_id (default, python-analysis, infra 등)
#   $2  planner_output_file   — planner 출력 파일 경로
#
assert_local_planner_image() {
  local expected_env_id="$1"
  local planner_output_file="$2"

  # environment_id → expected image 매핑
  local expected_image
  case "$expected_env_id" in
    default)         expected_image="ghcr.io/dlddu/pure-agent/claude-agent:latest" ;;
    python-analysis) expected_image="ghcr.io/dlddu/pure-agent/python-agent:latest" ;;
    infra)           expected_image="ghcr.io/dlddu/pure-agent/infra-agent:latest" ;;
    *)               expected_image="ghcr.io/dlddu/pure-agent/claude-agent:latest" ;;
  esac

  local actual
  actual=$(cat "$planner_output_file" | tr -d '[:space:]')

  if [[ "$expected_image" != "$actual" ]]; then
    echo "FAIL assert_local_planner_image: expected '${expected_image}' (${expected_env_id}) but got '${actual}'" >&2
    return 1
  fi

  log "assert_local_planner_image OK: ${actual}"
}

# ── assert_local_export_handler_exit ─────────────────────────────────────────
# export-handler 종료 코드 검증
#
# Arguments:
#   $1  expected  — 기대하는 종료 코드
#   $2  actual    — 실제 종료 코드
#
assert_local_export_handler_exit() {
  local expected="$1"
  local actual="$2"

  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL assert_local_export_handler_exit: expected exit ${expected} but got ${actual}" >&2
    return 1
  fi

  log "assert_local_export_handler_exit OK: ${actual}"
}

# ── assert_local_github_pr ───────────────────────────────────────────────────
# mock-gh pr create 호출 여부 검증
#
# Arguments:
#   $1  expected  — "true" (호출됨) 또는 "false" (호출 안됨), 기본값: "true"
#
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
