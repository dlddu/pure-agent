#!/usr/bin/env bash
# e2e/lib/common.sh — run-local.sh / run-argo.sh 공용 헬퍼 함수
#
# 이 파일은 직접 실행하지 않고, source하여 함수만 로드합니다.
# 호출 스크립트에서 다음 변수를 미리 설정해야 합니다:
#   LEVEL         — 테스트 레벨 (1, 2, 3)
#   SCENARIOS_DIR — 시나리오 YAML 디렉토리 경로
#
# 또한 log(), warn() 함수가 호출 스크립트에서 정의되어 있어야 합니다.
#
# Functions:
#   yaml_get <yaml_file> <yq_path>
#   discover_scenarios
#   prepare_cycle_fixtures <yaml_file> <cycle_index> <out_dir>

set -euo pipefail

# ── YAML helper ──────────────────────────────────────────────────────────────
# yq wrapper: "null" → empty string 변환.
yaml_get() {
  local yaml_file="$1"
  local path="$2"
  local value
  value=$(yq eval "$path" "$yaml_file" 2>/dev/null || echo "null")
  if [[ "$value" == "null" ]]; then
    echo ""
  else
    echo "$value"
  fi
}

# ── 시나리오 디스커버리 ──────────────────────────────────────────────────────
# SCENARIOS_DIR 내 YAML 파일 중 현재 LEVEL을 지원하는 시나리오 이름을 출력합니다.
discover_scenarios() {
  local yaml_file
  for yaml_file in "${SCENARIOS_DIR}"/*.yaml; do
    [[ -f "$yaml_file" ]] || continue
    local has_level
    has_level=$(yq eval ".level[] | select(. == ${LEVEL})" "$yaml_file" 2>/dev/null || true)
    [[ -n "$has_level" ]] || continue
    yaml_get "$yaml_file" '.name'
  done
}

# ── cycle fixture 준비 ──────────────────────────────────────────────────────
# 시나리오 YAML의 cycles[N]에서 export_config.json, agent_result.txt를 생성합니다.
#
# Arguments:
#   $1  yaml_file    — 시나리오 YAML 파일 경로
#   $2  cycle_index  — cycle 인덱스 (0-based)
#   $3  out_dir      — 파일을 배치할 디렉토리
prepare_cycle_fixtures() {
  local yaml_file="$1"
  local cycle_index="$2"
  local out_dir="$3"

  mkdir -p "$out_dir"

  # export_config: YAML → JSON
  local export_config_raw
  export_config_raw=$(yq eval ".cycles[${cycle_index}].export_config" "$yaml_file" 2>/dev/null || echo "null")

  if [[ "$export_config_raw" != "null" && -n "$export_config_raw" ]]; then
    yq eval -o=json ".cycles[${cycle_index}].export_config" "$yaml_file" \
      > "${out_dir}/export_config.json"
    log "Prepared export_config.json for cycle ${cycle_index}"
  else
    rm -f "${out_dir}/export_config.json"
    log "No export_config for cycle ${cycle_index}"
  fi

  # agent_result
  local agent_result
  agent_result=$(yq eval ".cycles[${cycle_index}].agent_result // \"\"" "$yaml_file" 2>/dev/null || echo "")

  if [[ -n "$agent_result" && "$agent_result" != "null" ]]; then
    echo "$agent_result" > "${out_dir}/agent_result.txt"
    log "Prepared agent_result.txt for cycle ${cycle_index}: $agent_result"
  else
    rm -f "${out_dir}/agent_result.txt"
  fi
}
