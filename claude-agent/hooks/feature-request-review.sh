#!/bin/bash
# Stop hook: 누락된 도구/기능에 대한 피드백을 수집
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

review_features() {
  hook_file_exists ".feature_review_done" && exit 0

  # 플래그 생성 (다음 시도에서는 통과하도록)
  touch "$WORK_DIR/.feature_review_done"

  hook_block << 'EOF'
작업을 종료하기 전에, 지금까지의 대화를 검토하세요.

다음과 같은 상황이 있었다면 mcp__pure-agent__request_feature를 호출하여 기능 요청을 제출하세요:
- 필요했지만 사용할 수 없었던 도구나 기능
- 네트워크 제한으로 접근할 수 없었던 외부 서비스나 API
- 기존 도구의 한계로 우회해야 했던 작업
- 더 나은 도구가 있었다면 더 효과적으로 완료할 수 있었던 작업

해당 사항이 없다면 그대로 작업을 종료하세요.
EOF
}

hook_run review_features
