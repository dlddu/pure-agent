#!/bin/bash
set -euo pipefail

# ─── Load library modules ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/validate.sh"
source "$SCRIPT_DIR/lib/mcp-config.sh"
source "$SCRIPT_DIR/lib/prompt.sh"
source "$SCRIPT_DIR/lib/claude-runner.sh"
source "$SCRIPT_DIR/lib/transcripts.sh"

# ─── Cleanup ────────────────────────────────────────────────
# Clean up temporary files on exit.
# RESULT_FILE, SESSION_ID_FILE, AGENT_OUTPUT_COPY are read by external
# components (Argo, export-handler, mcp-server) so they must NOT be removed.
cleanup() { rm -f "$AGENT_OUTPUT" 2>/dev/null || true; }
trap cleanup EXIT

# ─── Helpers ─────────────────────────────────────────────────

# Copy agent guidelines to working directory after volume mount.
_copy_agent_guidelines() {
  if ! cp "$CLAUDE_MD_SOURCE" "$WORK_DIR/CLAUDE.md" 2>/dev/null; then
    warn "Failed to copy CLAUDE.md to working directory"
  fi
}

# ─── Main ───────────────────────────────────────────────────

main() {
  log "Starting claude-agent"
  validate_env
  [ -d "$WORK_DIR" ] || die "Working directory does not exist: $WORK_DIR"
  [ -f "$EXTRACT_RESULT_FILTER" ] || die "Missing jq filter: $EXTRACT_RESULT_FILTER"

  log "Config: WORK_DIR=$WORK_DIR MCP_HOST=$MCP_HOST:$MCP_PORT"
  log "Previous output: $([ -n "${PREVIOUS_OUTPUT:-}" ] && echo "yes (${#PREVIOUS_OUTPUT} chars)" || echo "no")"

  cd "$WORK_DIR"
  _copy_agent_guidelines
  setup_mcp_config

  local agent_exit=0
  run_claude || agent_exit=$?

  extract_result
  collect_transcripts

  if [ "$agent_exit" -ne 0 ]; then
    warn "Agent completed with errors (exit=$agent_exit)"
  fi
  log "Done"
  return "$agent_exit"
}

# Allow sourcing for tests without executing main
if [ "${1:-}" != "--source-only" ]; then
  main "$@"
fi
