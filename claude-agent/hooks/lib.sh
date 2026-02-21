#!/bin/bash
# Claude Code stop hook shared utilities
#
# DESIGN: Hooks use fail-open semantics. We do NOT set -e because
# unhandled errors should allow stop (exit 0), not produce ambiguous
# exit codes. Each hook explicitly calls exit 0 or exit 2.
#
# Hook exit codes:
#   0 = pass (allow stop)
#   2 = block (prevent stop, stderr 메시지가 에이전트에게 전달)
#
# ─── How to add a new stop hook ─────────────────────────────
# 1. Create hooks/my-hook.sh (chmod +x)
# 2. Source this library: source "$(dirname "$0")/lib.sh"
# 3. Define a function with your logic:
#      my_check() {
#        hook_file_exists "something" && exit 0
#        hook_block "Missing something"
#      }
# 4. Call: hook_run my_check
# 5. Register in settings.json under hooks.Stop
# ────────────────────────────────────────────────────────────

# shellcheck source=../shared/defaults.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shared/defaults.sh"
WORK_DIR="${WORK_DIR:-$DEFAULT_WORK_DIR}"

# Maximum seconds to wait for hook input on stdin.
# Claude Code pipes JSON immediately; this prevents hangs if stdin never closes.
HOOK_INPUT_TIMEOUT=3

# stdin에서 hook input JSON 읽기 (잘못된 입력 시 fail-open)
hook_read_input() {
  HOOK_INPUT=$(timeout "$HOOK_INPUT_TIMEOUT" cat) || true
  if [ -z "$HOOK_INPUT" ] || ! jq -e . <<< "$HOOK_INPUT" >/dev/null 2>&1; then
    hook_log "Invalid or empty hook input; allowing stop"
    exit 0
  fi
}

# stop_hook_active 바이패스 플래그 확인.
# Claude Code가 세션을 강제 종료할 때 stop_hook_active=true를 설정하여
# hooks가 강제 종료를 차단하는 데드락을 방지한다.
hook_is_bypass_active() {
  [ "$(jq -r '.stop_hook_active // "false"' <<< "$HOOK_INPUT" 2>/dev/null)" = "true" ]
}

# WORK_DIR 하위 파일 존재 확인
# Usage: hook_file_exists "export_config.json"
hook_file_exists() {
  [ -n "${1:-}" ] && [ -f "$WORK_DIR/$1" ]
}

# 훅 이름으로 stderr 로깅
hook_log() {
  echo "[hook:$(basename "$0" .sh)] $*" >&2
}

# 에이전트 종료를 차단하고 stderr로 메시지 전달
# Usage: hook_block "message" 또는 hook_block <<'EOF' ... EOF
hook_block() {
  if [ $# -gt 0 ]; then
    echo "$*" >&2
  else
    cat >&2
  fi
  exit 2
}

# 표준 hook 라이프사이클 래퍼:
#   1. stdin에서 입력 읽기 (fail-open)
#   2. bypass 플래그 확인 (fail-open)
#   3. hook 함수 실행
# Usage: hook_run my_check_function
hook_run() {
  local hook_fn="${1:?hook_run requires a function name}"
  hook_read_input
  hook_is_bypass_active && exit 0
  "$hook_fn"
}
