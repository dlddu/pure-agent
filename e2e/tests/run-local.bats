#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/tests/run-local.bats — Level ① E2E 시나리오 테스트 (Docker Compose 기반)
#
# DLD-468: Level ① e2e 테스트 작성 (skipped)
#
# 테스트 구조:
#   - 모든 테스트는 skip 상태입니다.
#   - skip 제거 시 Docker Compose 환경에서 바로 실행 가능한 구조입니다.
#   - 각 테스트는 하나의 시나리오만 검증합니다.
#
# 전제 조건 (skip 제거 시 필요):
#   - docker (compose plugin 포함)
#   - curl, jq, yq
#   - e2e/docker-compose.yml
#   - e2e/run-local.sh
#
# 실행 방법:
#   bats e2e/tests/run-local.bats
#
# 개별 시나리오 실행:
#   SCENARIO=none-action bats e2e/tests/run-local.bats

# ── 경로 설정 ─────────────────────────────────────────────────────────────────
E2E_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCENARIOS_DIR="${E2E_DIR}/scenarios"
COMPOSE_FILE="${E2E_DIR}/docker-compose.yml"
RUN_LOCAL="${E2E_DIR}/run-local.sh"
MOCK_API_URL="${MOCK_API_URL:-http://localhost:4000}"

# ── 공통 setup / teardown ─────────────────────────────────────────────────────

setup() {
  # 각 테스트 전 임시 작업 디렉토리 생성
  export WORK_DIR="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$WORK_DIR"

  # run-local.sh를 --source-only 모드로 로드하여 헬퍼 함수만 가져옴
  # shellcheck disable=SC1090
  source "$RUN_LOCAL" --source-only
}

teardown() {
  # 각 테스트 후 Docker Compose 정리 (실패 시에도 실행)
  # skip 상태이므로 실제로는 실행되지 않음
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 1: none-action
#
# 검증 항목:
#   - Router 출력: false (stop)
#   - Export Handler 종료 코드: 0
#   - Linear 코멘트: 없음 (assertions.linear_comment 미정의)
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: none-action — router outputs false, export-handler exits 0" {
  # TODO: Activate when DLD-468 is implemented
  skip "Level 1 Docker Compose e2e: not yet implemented (DLD-468)"

  # Arrange
  local yaml_file="${SCENARIOS_DIR}/none-action.yaml"
  [ -f "$yaml_file" ]

  # docker compose up (mock-api)
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치
  local cycle_dir="${BATS_TEST_TMPDIR}/none-action-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # router 실행 (max_depth は YAML から読み込む)
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # Assert: router が "false" (stop) を出力すること
  local decision
  decision=$(cat "$router_output" | tr -d '[:space:]')
  [ "$decision" = "false" ]

  # export-handler 実行
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 終了コードが 0 であること
  [ "$eh_exit" -eq 0 ]

  # mock-api に Linear コメントの記録がないこと (none-action に assertions.linear_comment は未定義)
  local response
  response=$(curl -sf "${MOCK_API_URL}/assertions")
  local comment_count
  comment_count=$(echo "$response" | jq \
    '[.calls[] | select(.type == "mutation" and ((.operationName // "") | ascii_downcase | contains("comment")))] | length')
  # none-action では comment は 1 件 (summary のみ)
  [ "$comment_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 2: report-action
#
# 검증 항목:
#   - Router 출력: false (stop)
#   - Export Handler 종료 코드: 0
#   - Linear 코멘트: "분석 리포트" 포함
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: report-action — router outputs false, linear comment contains report" {
  # TODO: Activate when DLD-468 is implemented
  skip "Level 1 Docker Compose e2e: not yet implemented (DLD-468)"

  # Arrange
  local yaml_file="${SCENARIOS_DIR}/report-action.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치
  local cycle_dir="${BATS_TEST_TMPDIR}/report-action-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # router 실행 (max_depth は YAML から読み込む)
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # Assert: router が "false" (stop) を出力すること
  local decision
  decision=$(cat "$router_output" | tr -d '[:space:]')
  [ "$decision" = "false" ]

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 終了コードが 0 であること
  [ "$eh_exit" -eq 0 ]

  # Assert: Linear コメントに "分析リポート" が含まれること
  # (mock-api に createComment mutation が記録されているか確認)
  local response
  response=$(curl -sf "${MOCK_API_URL}/assertions")

  # summary コメント (1 件目)
  local summary_count
  summary_count=$(echo "$response" | jq \
    '[.calls[] | select(
        .type == "mutation" and
        ((.operationName // "") | ascii_downcase | contains("comment"))
     )] | length')
  [ "$summary_count" -ge 1 ]

  # report コメント: body に "분석 리포트" を含むこと
  local report_count
  report_count=$(echo "$response" | jq --arg body "분석 리포트" \
    '[.calls[] | select(
        .type == "mutation" and
        ((.body | tostring) | contains($body))
     )] | length')
  [ "$report_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 3: create-pr-action
#
# 검증 항목:
#   - Router 출력: false (stop)
#   - Export Handler 종료 코드: 0
#   - mock-gh 호출 기록: "gh pr create" 존재
#   - Linear 코멘트: PR URL 포함
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: create-pr-action — gh pr create called, linear comment contains PR URL" {
  # TODO: Activate when DLD-468 is implemented
  skip "Level 1 Docker Compose e2e: not yet implemented (DLD-468)"

  # Arrange
  local yaml_file="${SCENARIOS_DIR}/create-pr-action.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: fixture 배치
  local cycle_dir="${BATS_TEST_TMPDIR}/create-pr-action-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # router 실행 (max_depth は YAML から読み込む)
  local max_depth
  max_depth=$(yq eval '.max_depth // 5' "$yaml_file")
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose 0 "$max_depth" "$router_output"

  # Assert: router が "false" (stop) を出力すること
  local decision
  decision=$(cat "$router_output" | tr -d '[:space:]')
  [ "$decision" = "false" ]

  # export-handler 실행 (mock-gh를 PATH に優先させる)
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 終了コードが 0 であること
  [ "$eh_exit" -eq 0 ]

  # Assert: mock-gh の "gh pr create" 호출 기록が存在すること
  local pr_call_count
  pr_call_count=$(count_gh_pr_create_calls)
  [ "$pr_call_count" -ge 1 ]

  # Assert: Linear コメントに PR URL が含まれること
  # mock-gh は "https://github.com/mock-org/mock-repo/pull/1" を返す
  local response
  response=$(curl -sf "${MOCK_API_URL}/assertions")
  local pr_url_count
  pr_url_count=$(echo "$response" | jq --arg url "https://github.com/mock-org/mock-repo/pull" \
    '[.calls[] | select(
        .type == "mutation" and
        ((.body | tostring) | contains($url))
     )] | length')
  [ "$pr_url_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 4: continue-then-stop
#
# 검증 항목:
#   - cycle-0: Router 출력: true (continue)
#   - cycle-0 완료 후: /work/export_config.json 이 갱신/삭제됨
#   - cycle-1: Router 출력: false (stop)
#   - Export Handler 종료 코드: 0
#   - Linear 코멘트: "작업 완료" 포함
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: continue-then-stop — cycle-0 router outputs true, cycle-1 outputs false" {
  # TODO: Activate when DLD-468 is implemented
  skip "Level 1 Docker Compose e2e: not yet implemented (DLD-468)"

  # Arrange
  local yaml_file="${SCENARIOS_DIR}/continue-then-stop.yaml"
  [ -f "$yaml_file" ]

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # ── cycle-0 ────────────────────────────────────────────────────────────────
  local cycle0_dir="${BATS_TEST_TMPDIR}/continue-then-stop-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle0_dir"
  place_fixtures_via_mock_agent "$cycle0_dir"

  local cycle0_max_depth
  cycle0_max_depth=$(yq eval '.cycles[0].max_depth // .max_depth // 5' "$yaml_file")
  local router_output_0="${BATS_TEST_TMPDIR}/router_decision_0.txt"
  run_router_in_compose 0 "$cycle0_max_depth" "$router_output_0"

  # Assert cycle-0: router が "true" (continue) を出力すること
  local decision_0
  decision_0=$(cat "$router_output_0" | tr -d '[:space:]')
  [ "$decision_0" = "true" ]

  # cycle-0 export-handler 실행
  local eh_exit_0=0
  run_export_handler || eh_exit_0=$?
  [ "$eh_exit_0" -eq 0 ]

  # cycle-0 완료 후: export-handler が次の cycle のために /work/export_config.json を削除すること
  # (continue action では export_config.json を削除して次の cycle に委ねる)
  local export_config_deleted
  export_config_deleted=$(docker compose -f "$COMPOSE_FILE" \
    run --rm --entrypoint="" router \
    sh -c "[ -f /work/export_config.json ] && echo exists || echo deleted" 2>/dev/null)
  [ "$export_config_deleted" = "deleted" ]

  # ── cycle-1 ────────────────────────────────────────────────────────────────
  local cycle1_dir="${BATS_TEST_TMPDIR}/continue-then-stop-cycle1"
  prepare_cycle_fixtures "$yaml_file" 1 "$cycle1_dir"
  place_fixtures_via_mock_agent "$cycle1_dir"

  local cycle1_max_depth
  cycle1_max_depth=$(yq eval '.cycles[1].max_depth // .max_depth // 5' "$yaml_file")
  local router_output_1="${BATS_TEST_TMPDIR}/router_decision_1.txt"
  run_router_in_compose 1 "$cycle1_max_depth" "$router_output_1"

  # Assert cycle-1: router が "false" (stop) を出力すること
  local decision_1
  decision_1=$(cat "$router_output_1" | tr -d '[:space:]')
  [ "$decision_1" = "false" ]

  # cycle-1 export-handler 실행
  local eh_exit_1=0
  run_export_handler || eh_exit_1=$?
  [ "$eh_exit_1" -eq 0 ]

  # Assert: Linear コメントに "作業完了" が含まれること
  local response
  response=$(curl -sf "${MOCK_API_URL}/assertions")
  local work_done_count
  work_done_count=$(echo "$response" | jq --arg body "작업 완료" \
    '[.calls[] | select(
        .type == "mutation" and
        ((.body | tostring) | contains($body))
     )] | length')
  [ "$work_done_count" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 시나리오 5: depth-limit
#
# 검증 항목:
#   - Router 출력: false (stop) — depth >= max_depth - 1 のため強制終了
#   - Export Handler 종료 코드: 0
#
# 참고: depth-limit 시나리오는 level: [2] のみ定義 (Level 1 には未含)
# Level ① テストでは max_depth=2, depth=1 で router が stop を返すことを確認する
# ═══════════════════════════════════════════════════════════════════════════════

@test "scenario: depth-limit — router outputs false when depth reaches max_depth" {
  # TODO: Activate when DLD-468 is implemented
  skip "Level 1 Docker Compose e2e: not yet implemented (DLD-468)"

  # Arrange
  # depth-limit は level:[2] のみだが、Level ① テストとして
  # max_depth=2, depth=1 の組み合わせで router が stop することを検証する
  local yaml_file="${SCENARIOS_DIR}/depth-limit.yaml"
  [ -f "$yaml_file" ]

  # max_depth は YAML から読み込む (depth-limit: 2)
  local max_depth
  max_depth=$(yq eval '.max_depth // 2' "$yaml_file")

  # docker compose up
  compose_up
  wait_mock_api
  reset_mock_api

  # Cycle 0: export_config.json が null なので fixture なし
  local cycle_dir="${BATS_TEST_TMPDIR}/depth-limit-cycle0"
  prepare_cycle_fixtures "$yaml_file" 0 "$cycle_dir"
  place_fixtures_via_mock_agent "$cycle_dir"

  # router を depth=max_depth-1 で実行 (depth limit に到達する状態)
  local depth=$(( max_depth - 1 ))
  local router_output="${BATS_TEST_TMPDIR}/router_decision.txt"
  run_router_in_compose "$depth" "$max_depth" "$router_output"

  # Assert: router が "false" (stop) を出力すること (depth limit)
  local decision
  decision=$(cat "$router_output" | tr -d '[:space:]')
  [ "$decision" = "false" ]

  # export-handler 실행
  local eh_exit=0
  run_export_handler || eh_exit=$?

  # Assert: export-handler 終了コードが 0 であること
  [ "$eh_exit" -eq 0 ]
}
