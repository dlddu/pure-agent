#!/bin/sh
# tests/mock-planner/planner.sh — Unit E2E용 mock planner
#
# mock-api의 /v1/messages에 HTTP 요청하여 환경 선택 결과를 반환하는 경량 mock.
# 프로덕션 planner(Claude Code CLI 기반)는 mock-api와 호환되지 않으므로
# Unit E2E에서는 이 스크립트를 사용합니다.
#
# 사용법:
#   planner.sh --prompt "task" --output /path/to/output.txt [--raw-id-output /path/to/raw.txt]
#
# 환경 변수:
#   ANTHROPIC_BASE_URL    — mock-api URL (예: http://mock-api:4000)
#   CLAUDE_CODE_OAUTH_TOKEN — API 키 (mock에서는 무시됨)

set -eu

# ── Parse arguments ─────────────────────────────────────────────────────────
PROMPT=""
OUTPUT=""
RAW_ID_OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prompt)    PROMPT="$2";        shift 2 ;;
    --output)    OUTPUT="$2";        shift 2 ;;
    --raw-id-output) RAW_ID_OUTPUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$OUTPUT" ]; then
  echo "ERROR: --output is required" >&2
  exit 2
fi

# ── Environment registry ───────────────────────────────────────────────────
resolve_image() {
  case "$1" in
    python-analysis) echo "ghcr.io/dlddu/pure-agent/python-agent:latest" ;;
    infra)           echo "ghcr.io/dlddu/pure-agent/infra-agent:latest" ;;
    *)               echo "ghcr.io/dlddu/pure-agent/claude-agent:latest" ;;
  esac
}

# ── Call mock-api /v1/messages ──────────────────────────────────────────────
BASE_URL="${ANTHROPIC_BASE_URL:-}"
if [ -z "$BASE_URL" ]; then
  echo "WARN: ANTHROPIC_BASE_URL not set, using default" >&2
  resolve_image "default" > "$OUTPUT"
  [ -n "$RAW_ID_OUTPUT" ] && echo "_NO_BASE_URL" > "$RAW_ID_OUTPUT"
  exit 0
fi

RESPONSE=$(wget -qO- --header="Content-Type: application/json" \
  --header="x-api-key: ${CLAUDE_CODE_OAUTH_TOKEN:-}" \
  --header="anthropic-version: 2023-06-01" \
  --post-data "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":\"${PROMPT}\"}]}" \
  "${BASE_URL}/v1/messages" 2>/dev/null) || {
  echo "WARN: API call failed, using default" >&2
  resolve_image "default" > "$OUTPUT"
  [ -n "$RAW_ID_OUTPUT" ] && echo "_HTTP_ERROR" > "$RAW_ID_OUTPUT"
  exit 0
}

# ── Parse response ──────────────────────────────────────────────────────────
# Extract environment_id from the JSON response text field
ENV_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json, re
resp = json.load(sys.stdin)
text = resp.get('content', [{}])[0].get('text', '')
m = re.search(r'\{[^}]*\}', text)
if m:
    parsed = json.loads(m.group())
    print(parsed.get('environment_id', 'default'))
else:
    print('default')
" 2>/dev/null) || ENV_ID="default"

echo "[mock-planner] environment_id=$ENV_ID" >&2

IMAGE=$(resolve_image "$ENV_ID")
echo "$IMAGE" > "$OUTPUT"
[ -n "$RAW_ID_OUTPUT" ] && echo "$ENV_ID" > "$RAW_ID_OUTPUT"

echo "[mock-planner] selected: $IMAGE" >&2
