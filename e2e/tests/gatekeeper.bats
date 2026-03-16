#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/tests/gatekeeper.bats — gatekeeper.sh 헬퍼 함수 단위 테스트
#
# DLD-781: Gatekeeper 통합 구현 전 단위 테스트 (Red Phase)
#
# 테스트 범위:
#   - GATEKEEPER_URL 환경 변수 미설정 시 각 함수가 에러를 반환하는지 검증
#   - gatekeeper.sh를 --source-only 모드로 로드하여 함수 시그니처 확인
#
# 전제 조건:
#   - bats-core
#   - e2e/lib/gatekeeper.sh
#
# 실행 방법:
#   bats e2e/tests/gatekeeper.bats

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_gatekeeper
  # 각 테스트 전 GATEKEEPER_URL 초기화 (미설정 상태로 시작)
  unset GATEKEEPER_URL
}

# ── GATEKEEPER_URL 미설정 에러 검증 ──────────────────────────────────────────
#
# gatekeeper.sh의 모든 함수는 GATEKEEPER_URL이 설정되지 않으면
# `: "${GATEKEEPER_URL:?GATEKEEPER_URL must be set}"` 가드로 인해
# non-zero exit code를 반환해야 합니다.

@test "gatekeeper_signup: fails with non-zero exit when GATEKEEPER_URL is not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_signup "testuser" "testpassword"

  # Assert
  [ "$status" -ne 0 ]
}

@test "gatekeeper_signup: error message mentions GATEKEEPER_URL when not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_signup "testuser" "testpassword"

  # Assert
  [[ "$output" == *"GATEKEEPER_URL"* ]]
}

@test "gatekeeper_login: fails with non-zero exit when GATEKEEPER_URL is not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_login "testuser" "testpassword"

  # Assert
  [ "$status" -ne 0 ]
}

@test "gatekeeper_login: error message mentions GATEKEEPER_URL when not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_login "testuser" "testpassword"

  # Assert
  [[ "$output" == *"GATEKEEPER_URL"* ]]
}

@test "gatekeeper_approve: fails with non-zero exit when GATEKEEPER_URL is not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_approve "request-id-123" "jwt-token-abc"

  # Assert
  [ "$status" -ne 0 ]
}

@test "gatekeeper_approve: error message mentions GATEKEEPER_URL when not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_approve "request-id-123" "jwt-token-abc"

  # Assert
  [[ "$output" == *"GATEKEEPER_URL"* ]]
}

@test "gatekeeper_reject: fails with non-zero exit when GATEKEEPER_URL is not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_reject "request-id-123" "jwt-token-abc"

  # Assert
  [ "$status" -ne 0 ]
}

@test "gatekeeper_reject: error message mentions GATEKEEPER_URL when not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_reject "request-id-123" "jwt-token-abc"

  # Assert
  [[ "$output" == *"GATEKEEPER_URL"* ]]
}

@test "gatekeeper_get_pending: fails with non-zero exit when GATEKEEPER_URL is not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_get_pending "jwt-token-abc"

  # Assert
  [ "$status" -ne 0 ]
}

@test "gatekeeper_get_pending: error message mentions GATEKEEPER_URL when not set" {
  # Arrange
  unset GATEKEEPER_URL

  # Act
  run gatekeeper_get_pending "jwt-token-abc"

  # Assert
  [[ "$output" == *"GATEKEEPER_URL"* ]]
}
