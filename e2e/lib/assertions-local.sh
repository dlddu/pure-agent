#!/usr/bin/env bash
# e2e/lib/assertions-local.sh — Level ① (Docker Compose) 전용 assertion helpers
#
# run-local.sh에서 추출된 로컬 환경 전용 assertion 함수들입니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수/함수를 미리 설정해야 합니다:
#   MOCK_API_URL    — mock-api 베이스 URL
#   log()           — 로깅 함수
#   count_gh_pr_create_calls()  — lib/compose.sh에서 제공
#
# Functions:
#   assert_local_router_decision <expected> <router_output_file>
#   assert_local_linear_comment <body_contains>
#   assert_local_export_handler_exit <expected> <actual>
#   assert_local_github_pr [expected]

set -euo pipefail

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || true
fi

# ── assert_local_router_decision ─────────────────────────────────────────────
# router 결정값 검증
#
# Arguments:
#   $1  expected            — "stop", "continue", "true", "false"
#   $2  router_output_file  — router 출력 파일 경로
#
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

# ── assert_local_linear_comment ──────────────────────────────────────────────
# mock-api /assertions 기반 Linear comment 검증
#
# Arguments:
#   $1  body_contains  — 코멘트 body에 포함되어야 하는 문자열
#
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
