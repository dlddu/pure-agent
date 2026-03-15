#!/usr/bin/env bash
# e2e/lib/gatekeeper.sh — Gatekeeper API curl 헬퍼 함수
#
# DLD-780: web_fetch e2e 테스트 (skip 상태) — 함수 시그니처 정의
# DLD-781: 실제 curl 구현
#
# Usage in BATS: load_gatekeeper 함수를 통해 --source-only 모드로 로드합니다.
#
# 필수 환경 변수:
#   GATEKEEPER_URL  — Gatekeeper 베이스 URL (예: http://localhost:8080)
#
# Functions:
#   gatekeeper_signup  <username> <password>
#   gatekeeper_login   <username> <password>
#   gatekeeper_approve <request_id> <jwt_token>
#   gatekeeper_reject  <request_id> <jwt_token>
#   gatekeeper_get_pending <jwt_token>

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  true
fi

# ── gatekeeper_signup ─────────────────────────────────────────────────────────
# 테스트 사용자를 Gatekeeper에 등록합니다.
#
# Arguments:
#   $1  username  — 등록할 사용자명
#   $2  password  — 등록할 비밀번호
#
# Returns:
#   0  — 등록 성공 (또는 이미 존재)
#   1  — 등록 실패 (서버 오류)
#
gatekeeper_signup() {
  local username="$1"
  local password="$2"
  : "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"

  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST "${GATEKEEPER_URL}/api/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${username}\",\"password\":\"${password}\"}" \
    2>/dev/null) || true

  # 201 Created = 성공, 409 Conflict = 이미 존재 (둘 다 허용)
  case "$http_code" in
    201|409) return 0 ;;
    *)
      echo "gatekeeper_signup failed: HTTP ${http_code}" >&2
      return 1
      ;;
  esac
}

# ── gatekeeper_login ──────────────────────────────────────────────────────────
# Gatekeeper에 로그인하여 JWT 토큰을 획득합니다.
#
# Arguments:
#   $1  username  — 로그인할 사용자명
#   $2  password  — 로그인할 비밀번호
#
# Outputs:
#   JWT 토큰 문자열 (stdout)
#
# Returns:
#   0  — 로그인 성공
#   1  — 로그인 실패 (인증 오류 또는 서버 오류)
#
gatekeeper_login() {
  local username="$1"
  local password="$2"
  : "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"

  local response
  response=$(curl -sf \
    -X POST "${GATEKEEPER_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${username}\",\"password\":\"${password}\"}" \
    2>/dev/null) || {
    echo "gatekeeper_login: curl failed" >&2
    return 1
  }

  local token
  token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null || true)

  if [[ -z "$token" ]]; then
    echo "gatekeeper_login: no token in response: ${response}" >&2
    return 1
  fi

  echo "$token"
}

# ── gatekeeper_approve ────────────────────────────────────────────────────────
# 지정한 승인 요청을 승인 처리합니다.
#
# Arguments:
#   $1  request_id  — 승인 처리할 요청 ID
#   $2  jwt_token   — 인증에 사용할 JWT 토큰
#
# Returns:
#   0  — 승인 성공
#   1  — 승인 실패 (요청 없음, 권한 없음, 서버 오류)
#
gatekeeper_approve() {
  local request_id="$1"
  local jwt_token="$2"
  : "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"

  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X PATCH "${GATEKEEPER_URL}/api/requests/${request_id}/approve" \
    -H "Authorization: Bearer ${jwt_token}" \
    -H "Content-Type: application/json" \
    2>/dev/null) || true

  case "$http_code" in
    200|204) return 0 ;;
    *)
      echo "gatekeeper_approve failed: HTTP ${http_code} for request_id=${request_id}" >&2
      return 1
      ;;
  esac
}

# ── gatekeeper_reject ─────────────────────────────────────────────────────────
# 지정한 승인 요청을 거절 처리합니다.
#
# Arguments:
#   $1  request_id  — 거절 처리할 요청 ID
#   $2  jwt_token   — 인증에 사용할 JWT 토큰
#
# Returns:
#   0  — 거절 성공
#   1  — 거절 실패 (요청 없음, 권한 없음, 서버 오류)
#
gatekeeper_reject() {
  local request_id="$1"
  local jwt_token="$2"
  : "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"

  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X PATCH "${GATEKEEPER_URL}/api/requests/${request_id}/reject" \
    -H "Authorization: Bearer ${jwt_token}" \
    -H "Content-Type: application/json" \
    2>/dev/null) || true

  case "$http_code" in
    200|204) return 0 ;;
    *)
      echo "gatekeeper_reject failed: HTTP ${http_code} for request_id=${request_id}" >&2
      return 1
      ;;
  esac
}

# ── gatekeeper_get_pending ────────────────────────────────────────────────────
# PENDING 상태의 승인 요청 목록을 조회합니다.
#
# Arguments:
#   $1  jwt_token  — 인증에 사용할 JWT 토큰
#
# Outputs:
#   PENDING 요청 목록 JSON (stdout)
#
# Returns:
#   0  — 조회 성공
#   1  — 조회 실패 (권한 없음, 서버 오류)
#
gatekeeper_get_pending() {
  local jwt_token="$1"
  : "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"

  local response
  response=$(curl -sf \
    -X GET "${GATEKEEPER_URL}/api/requests?status=pending" \
    -H "Authorization: Bearer ${jwt_token}" \
    2>/dev/null) || {
    echo "gatekeeper_get_pending: curl failed" >&2
    return 1
  }

  echo "$response"
}
