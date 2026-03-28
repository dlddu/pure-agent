#!/usr/bin/env bash
# e2e/lib/mock-gh.sh — mock-gh (gh CLI mock) 헬퍼 함수
#
# mock-gh 호출 기록 조회 및 git repo 셋업 함수를 제공합니다.
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
#
# 호출 스크립트에서 다음 변수를 미리 설정해야 합니다:
#   COMPOSE_FILE    — docker-compose.yml 경로
#
# 또한 log() 함수가 호출 스크립트에서 정의되어 있어야 합니다.
#
# Functions:
#   count_gh_pr_create_calls
#   setup_mock_git_repo

set -euo pipefail

# ── mock-gh 호출 기록 조회 ────────────────────────────────────────────────────
count_gh_pr_create_calls() {
  local count
  count=$(docker compose -f "$COMPOSE_FILE" \
    run --rm \
    --entrypoint="" \
    export-handler \
    sh -c "ls /gh-calls/pr-create-* 2>/dev/null | wc -l | tr -d ' '") || echo "0"
  echo "${count:-0}"
}

# ── mock git repo 셋업 ───────────────────────────────────────────────────────
# create-pr-action 시나리오에서 사용하는 bare remote + working repo를
# /work 공유 볼륨에 생성합니다.
#
setup_mock_git_repo() {
  log "Setting up mock git repo on shared volume ..."
  docker compose -f "$COMPOSE_FILE" \
    run --rm --entrypoint="" \
    --user root \
    export-handler \
    sh -c '
      set -e
      # Create a bare "remote" repo
      git init --bare /work/repo-remote.git
      # Create the working repo
      git init /work/repo
      cd /work/repo
      git config user.email "test@e2e.local"
      git config user.name "E2E Test"
      git remote add origin /work/repo-remote.git
      # Initial commit on main
      echo "init" > README.md
      git add README.md
      git commit -m "Initial commit"
      git push -u origin HEAD:main
      # Create feature branch with a commit
      git checkout -b feat/test-branch
      echo "hello" > hello.txt
      git add hello.txt
      git commit -m "Add hello.txt"
      # Ensure node user can access the repo and gh-calls
      chown -R node:node /work/repo /work/repo-remote.git /gh-calls
    '
}
