#!/bin/bash
# Stop hook: export_config.json 없이 종료하는 것을 차단
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

check_export_config() {
  hook_file_exists "export_config.json" && exit 0

  hook_block << 'EOF'
export_config.json이 없습니다.
먼저 get_export_actions 툴을 호출하여 사용 가능한 action 목록과 각 action의 필수 필드를 확인한 뒤,
적절한 action을 선택하여 set_export_config 툴을 호출하세요.
작업을 완료하지 못한 경우에도 action='none'으로 설정하고 summary에 현재 상태와 이유를 기술하세요.
EOF
}

hook_run check_export_config
