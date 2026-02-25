#!/bin/sh
# mock-router — Level 2 E2E용 router mock
# 실제 router와 동일한 CLI 인터페이스를 사용하되, 항상 depth 체크를 수행합니다.
# 실제 router는 actions:["continue"]일 때 depth를 무시하지만,
# mock-router는 depth >= max_depth - 1이면 항상 false를 반환합니다.
set -eu

DEPTH=0
MAX_DEPTH=10
EXPORT_CONFIG=""
OUTPUT="/tmp/continue.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --depth)         DEPTH="$2"; shift 2 ;;
    --max-depth)     MAX_DEPTH="$2"; shift 2 ;;
    --export-config) EXPORT_CONFIG="$2"; shift 2 ;;
    --output)        OUTPUT="$2"; shift 2 ;;
    *)               shift ;;
  esac
done

RESULT="false"

# depth < max_depth - 1 인 경우에만 continue 가능
if [ "$DEPTH" -lt "$((MAX_DEPTH - 1))" ]; then
  if echo "$EXPORT_CONFIG" | grep -q '"continue"' 2>/dev/null; then
    RESULT="true"
  elif [ -z "$EXPORT_CONFIG" ] || [ "$EXPORT_CONFIG" = "{}" ] || [ "$EXPORT_CONFIG" = "null" ]; then
    RESULT="true"
  fi
fi

echo "$RESULT" > "$OUTPUT"
echo "[mock-router] depth=$DEPTH/$MAX_DEPTH export_config_len=${#EXPORT_CONFIG} -> $RESULT" >&2
