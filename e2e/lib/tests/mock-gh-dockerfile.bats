#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/lib/tests/mock-gh-dockerfile.bats
#
# DLD-467: mock-gh Dockerfile 빌드 검증 테스트
#
# mock-gh Dockerfile이 올바르게 작성되어 있는지 검증합니다.
# Docker 데몬이 필요한 테스트는 DOCKER_AVAILABLE 환경 변수로 분기합니다.
#
# 테스트 범주:
#   1. Dockerfile 파일 존재 및 구조 검증 (Docker 데몬 불필요)
#   2. Dockerfile 내용 검증: alpine 기반, mock-gh 스크립트 복사, 실행 권한
#   3. 빌드된 이미지 동작 검증 (Docker 데몬 필요)
#
# 실행 방법:
#   bats e2e/lib/tests/mock-gh-dockerfile.bats
#
# Docker 이미지 빌드 테스트 활성화:
#   DOCKER_AVAILABLE=1 bats e2e/lib/tests/mock-gh-dockerfile.bats

source "$BATS_TEST_DIRNAME/test-helper.sh"

# ── 공통 설정 ───────────────────────────────────────────────────────────────

setup() {
  common_setup

  # mock-gh 디렉토리 경로 (BATS_TEST_DIRNAME = e2e/lib/tests)
  MOCK_GH_DIR="$(cd "$BATS_TEST_DIRNAME/../../mock-gh" && pwd)"
  export MOCK_GH_DIR

  DOCKERFILE="$MOCK_GH_DIR/Dockerfile"
  export DOCKERFILE
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Dockerfile 파일 존재 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "mock-gh Dockerfile: e2e/mock-gh/Dockerfile 파일이 존재한다" {
  [ -f "$DOCKERFILE" ]
}

@test "mock-gh Dockerfile: Dockerfile이 비어있지 않다" {
  [ -s "$DOCKERFILE" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. Dockerfile 내용 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "mock-gh Dockerfile: alpine 기반 이미지를 사용한다 (FROM alpine)" {
  # mock-agent Dockerfile 패턴과 동일하게 alpine 기반이어야 합니다.
  grep -qi "FROM alpine" "$DOCKERFILE"
}

@test "mock-gh Dockerfile: gh 스크립트를 이미지에 COPY한다" {
  # mock-gh 스크립트(gh)를 이미지에 복사하는 COPY 명령이 있어야 합니다.
  grep -q "COPY.*gh" "$DOCKERFILE"
}

@test "mock-gh Dockerfile: gh 스크립트에 실행 권한을 부여한다 (chmod +x 또는 RUN chmod)" {
  # gh 스크립트가 컨테이너 내에서 실행 가능해야 합니다.
  grep -q "chmod" "$DOCKERFILE"
}

@test "mock-gh Dockerfile: /usr/local/bin/gh 또는 /app/gh 경로로 설치한다" {
  # 컨테이너 내에서 gh 명령이 PATH에 있거나 명시적 경로로 접근 가능해야 합니다.
  # /usr/local/bin/gh 또는 /app/gh 경로 중 하나를 사용해야 합니다.
  grep -qE "/usr/local/bin/gh|/app/gh" "$DOCKERFILE"
}

@test "mock-gh Dockerfile: bash 또는 sh 셸이 설치되어 있다" {
  # mock-gh 스크립트가 bash/sh 기반이므로 셸이 설치되어야 합니다.
  # alpine 기반이면 apk add bash 또는 sh가 기본 포함되어야 합니다.
  grep -qiE "bash|RUN apk" "$DOCKERFILE"
}

@test "mock-gh Dockerfile: GH_CALLS_DIR 환경 변수 기본값이 설정되거나 스크립트에서 처리된다" {
  # mock-gh 스크립트가 GH_CALLS_DIR 환경 변수를 사용합니다.
  # Dockerfile에서 ENV로 설정하거나 스크립트 자체에서 기본값을 처리합니다.
  # gh 스크립트에서 이미 `: "${GH_CALLS_DIR:=/tmp/gh-calls}"` 처리를 하고 있으므로
  # Dockerfile에서 ENV를 명시적으로 설정하지 않아도 됩니다.
  # 여기서는 gh 스크립트가 GH_CALLS_DIR 기본값을 처리하는지 확인합니다.
  local gh_script="$MOCK_GH_DIR/gh"
  [ -f "$gh_script" ]
  grep -q "GH_CALLS_DIR" "$gh_script"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. mock-gh 스크립트 파일 존재 및 실행 가능성 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "mock-gh 스크립트: e2e/mock-gh/gh 파일이 존재한다" {
  local gh_script="$MOCK_GH_DIR/gh"
  [ -f "$gh_script" ]
}

@test "mock-gh 스크립트: 실행 권한이 있다" {
  local gh_script="$MOCK_GH_DIR/gh"
  [ -x "$gh_script" ]
}

@test "mock-gh 스크립트: bash 또는 sh shebang으로 시작한다" {
  local gh_script="$MOCK_GH_DIR/gh"
  local first_line
  first_line=$(head -1 "$gh_script")
  [[ "$first_line" == "#!/usr/bin/env bash" ]] \
    || [[ "$first_line" == "#!/bin/bash" ]] \
    || [[ "$first_line" == "#!/bin/sh" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Docker 이미지 빌드 검증 (Docker 데몬 필요)
#    DOCKER_AVAILABLE=1 환경 변수로 활성화합니다.
# ═══════════════════════════════════════════════════════════════════════════════

@test "mock-gh Dockerfile: docker build가 오류 없이 완료된다" {
  # Docker 데몬이 없는 환경(예: CI unit test)에서는 skip합니다.
  if [[ "${DOCKER_AVAILABLE:-0}" != "1" ]]; then
    skip "Docker 데몬 미사용 환경 — DOCKER_AVAILABLE=1 으로 활성화"
  fi

  # Arrange: 이미지 이름 (테스트용 임시 태그)
  local image_tag="pure-agent/mock-gh:bats-test-$$"

  # Act: Dockerfile 빌드
  run docker build -t "$image_tag" "$MOCK_GH_DIR"

  # Cleanup (빌드 성공/실패 무관하게 이미지 제거)
  docker rmi "$image_tag" 2>/dev/null || true

  # Assert: 빌드가 성공해야 합니다.
  [ "$status" -eq 0 ]
}

@test "mock-gh Dockerfile: 빌드된 이미지에서 gh pr create가 실행된다" {
  if [[ "${DOCKER_AVAILABLE:-0}" != "1" ]]; then
    skip "Docker 데몬 미사용 환경 — DOCKER_AVAILABLE=1 으로 활성화"
  fi

  # Arrange
  local image_tag="pure-agent/mock-gh:bats-test-$$"
  docker build -t "$image_tag" "$MOCK_GH_DIR" >/dev/null 2>&1

  # Act: 컨테이너 내에서 gh pr create 실행
  run docker run --rm \
    -e GH_CALLS_DIR=/tmp/gh-calls \
    "$image_tag" \
    gh pr create --title "Test PR" --body "body" --base main

  docker rmi "$image_tag" 2>/dev/null || true

  # Assert: 종료 코드 0, PR URL 출력
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://"* ]]
  [[ "$output" == *"/pull/"* ]]
}

@test "mock-gh Dockerfile: 빌드된 이미지에서 gh auth status가 실행된다" {
  if [[ "${DOCKER_AVAILABLE:-0}" != "1" ]]; then
    skip "Docker 데몬 미사용 환경 — DOCKER_AVAILABLE=1 으로 활성화"
  fi

  local image_tag="pure-agent/mock-gh:bats-test-$$"
  docker build -t "$image_tag" "$MOCK_GH_DIR" >/dev/null 2>&1

  run docker run --rm "$image_tag" gh auth status

  docker rmi "$image_tag" 2>/dev/null || true

  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
