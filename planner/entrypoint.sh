#!/bin/bash
set -euo pipefail

# ─── Load library modules ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/validate.sh"
source "$SCRIPT_DIR/lib/environments.sh"
source "$SCRIPT_DIR/lib/mcp-config.sh"
source "$SCRIPT_DIR/lib/prompt.sh"
source "$SCRIPT_DIR/lib/claude-runner.sh"
source "$SCRIPT_DIR/lib/transcripts.sh"

# ─── Cleanup ────────────────────────────────────────────────
cleanup() { rm -f "$CLAUDE_OUTPUT" "$MCP_CONFIG" 2>/dev/null || true; }
trap cleanup EXIT

# ─── Argument Parsing ───────────────────────────────────────
parse_args() {
  OUTPUT=""
  RAW_ID_OUTPUT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt)
        PROMPT="${2:?--prompt requires a value}"
        export PROMPT
        shift 2
        ;;
      --output)
        OUTPUT="${2:?--output requires a value}"
        shift 2
        ;;
      --raw-id-output)
        RAW_ID_OUTPUT="${2:-}"
        shift 2
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

# ─── Output Helpers ─────────────────────────────────────────

_write_output() {
  local value="$1" path="$2"
  echo "$value" > "$path"
  log "Output: $value -> $path"
}

_write_fallback() {
  if [ -n "$OUTPUT" ]; then
    echo "$DEFAULT_IMAGE" > "$OUTPUT"
    log "Wrote fallback output: $DEFAULT_IMAGE -> $OUTPUT"
  fi
}

# ─── Main ───────────────────────────────────────────────────

main() {
  log "Starting planner"
  parse_args "$@"

  [ -n "$OUTPUT" ] || die "--output is required"
  validate_env

  log "Config: MCP_HOST=${MCP_HOST:-<unset>} MCP_PORT=$MCP_PORT"

  setup_mcp_config

  # Run Claude Code CLI (always returns 0; logs warnings on failure)
  run_claude

  # Save planner transcript to shared volume for S3 upload by gate
  save_planner_transcript

  # Extract environment ID from Claude output
  local raw_id
  raw_id="$(extract_environment_id)"

  if [ -z "$raw_id" ]; then
    log "No environment_id extracted, using default"
    _write_output "$DEFAULT_IMAGE" "$OUTPUT"
    [ -n "$RAW_ID_OUTPUT" ] && _write_output "_PARSE_EMPTY" "$RAW_ID_OUTPUT"
    log "Done (default)"
    return 0
  fi

  log "LLM raw response: environment_id=$raw_id"

  local image
  image="$(resolve_image "$raw_id")"
  log "LLM selected environment: $raw_id -> $image"

  _write_output "$image" "$OUTPUT"
  [ -n "$RAW_ID_OUTPUT" ] && _write_output "$raw_id" "$RAW_ID_OUTPUT"

  log "Done"
}

# Allow sourcing for tests without executing main
if [ "${1:-}" = "--source-only" ]; then
  return 0 2>/dev/null || true
fi

# Error boundary: always produce output, even on crash
main "$@" || {
  rc=$?
  warn "Planner crashed (exit=$rc)"
  _write_fallback
  exit "$rc"
}
