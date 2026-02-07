#!/bin/bash
INPUT=$(cat)

# Prevent infinite loops: if Stop hook already triggered once, allow stopping
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi

# Check if export_config.json exists
if [ -f /work/export_config.json ]; then
  exit 0
fi

# Block stopping - stderr message is fed back to the agent
echo "export_config.json이 없습니다. 반드시 set_export_config 툴을 호출하세요. 작업을 완료하지 못한 경우에도 action='none'으로 설정하고 summary에 현재 상태와 이유를 기술하세요." >&2
exit 2
