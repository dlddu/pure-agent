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

if [ -f "$SCENARIO_DIR/export_config.json" ]; then
  mkdir -p "$WORK_DIR"
  cp "$SCENARIO_DIR/export_config.json" "$WORK_DIR/export_config.json"
fi

# ── Write agent_result.txt ────────────────────────────────────────────────────

if [ -f "$SCENARIO_DIR/agent_result.txt" ]; then
  cp "$SCENARIO_DIR/agent_result.txt" /tmp/agent_result.txt
else
  # Default: empty result for scenarios that don't require a specific result
  : > /tmp/agent_result.txt
fi

# ── Generate mock transcripts ─────────────────────────────────────────────────
# Create mock transcript files in /work/.transcripts/ so gate can upload them to S3.

TRANSCRIPT_DIR="${WORK_DIR}/.transcripts"
SESSION_ID="mock-session-$(date +%s)"

mkdir -p "$TRANSCRIPT_DIR"
cat > "$TRANSCRIPT_DIR/${SESSION_ID}.jsonl" <<JSONL
{"type":"assistant","message":"mock transcript entry","timestamp":"$(date -Iseconds)"}
{"type":"result","result":"mock agent completed","session_id":"${SESSION_ID}"}
JSONL

# If scenario provides custom transcript fixtures, copy them over
if [ -d "$SCENARIO_DIR/transcripts" ]; then
  cp "$SCENARIO_DIR/transcripts"/*.jsonl "$TRANSCRIPT_DIR/" 2>/dev/null || true
fi

# ── Write dummy session ID ────────────────────────────────────────────────────

echo "$SESSION_ID" > /tmp/session_id.txt
