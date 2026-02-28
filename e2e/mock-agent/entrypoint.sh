#!/usr/bin/env bash
# mock-agent entrypoint
# Reads fixtures from SCENARIO_DIR and writes outputs to agreed-upon locations.
#
# Contract:
#   Input  (SCENARIO_DIR):
#     export_config.json  — copied to /work/export_config.json  (optional)
#     agent_result.txt    — written to /tmp/agent_result.txt    (optional)
#   Output:
#     /tmp/agent_result.txt  — agent result text
#     /tmp/session_id.txt    — dummy session identifier

set -euo pipefail

# ── Validate required environment ─────────────────────────────────────────────

: "${SCENARIO_DIR:?SCENARIO_DIR must be set}"
: "${WORK_DIR:=/work}"

# ── Copy export_config.json if present ───────────────────────────────────────

MARKER_FILE="$WORK_DIR/.mock-agent-ran"

if [ -f "$SCENARIO_DIR/export_config.json" ]; then
  mkdir -p "$WORK_DIR"
  if [ ! -f "$MARKER_FILE" ]; then
    # 첫 번째 실행: ConfigMap의 export_config를 /work에 복사
    cp "$SCENARIO_DIR/export_config.json" "$WORK_DIR/export_config.json"
  fi
  # 이후 실행에서는 export_config를 복사하지 않음 (router가 삭제했으면 비어있음)
fi

# 마커 파일 생성 (첫 실행 표시)
touch "$MARKER_FILE"

# ── Write agent_result.txt ────────────────────────────────────────────────────

if [ -f "$SCENARIO_DIR/agent_result.txt" ]; then
  cp "$SCENARIO_DIR/agent_result.txt" /tmp/agent_result.txt
else
  # Default: empty result for scenarios that don't require a specific result
  : > /tmp/agent_result.txt
fi

# ── Write dummy session ID ────────────────────────────────────────────────────

echo "mock-session-$(date +%s)" > /tmp/session_id.txt
