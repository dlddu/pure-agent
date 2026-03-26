#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/planner.sh
#
# planner assertion/helper 함수의 유닛 테스트입니다.
# mock-api 서버는 Python mini HTTP 서버로 시뮬레이션합니다.

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_planner
}

# ── assert_planner_image ──────────────────────────────────────────────────────

@test "assert_planner_image: passes when output file contains expected substring" {
  echo "ghcr.io/dlddu/pure-agent/python-agent:latest" > "$WORK_DIR/image.txt"
  run assert_planner_image "$WORK_DIR/image.txt" "python-agent"
  [ "$status" -eq 0 ]
}

@test "assert_planner_image: passes when expected is exact match" {
  echo "ghcr.io/dlddu/pure-agent/claude-agent:latest" > "$WORK_DIR/image.txt"
  run assert_planner_image "$WORK_DIR/image.txt" "ghcr.io/dlddu/pure-agent/claude-agent:latest"
  [ "$status" -eq 0 ]
}

@test "assert_planner_image: fails when output does not contain expected substring" {
  echo "ghcr.io/dlddu/pure-agent/claude-agent:latest" > "$WORK_DIR/image.txt"
  run assert_planner_image "$WORK_DIR/image.txt" "python-agent"
  [ "$status" -ne 0 ]
}

@test "assert_planner_image: fails when output file does not exist" {
  run assert_planner_image "$WORK_DIR/nonexistent.txt" "claude-agent"
  [ "$status" -ne 0 ]
}

@test "assert_planner_image: failure output mentions expected and actual values" {
  echo "ghcr.io/dlddu/pure-agent/claude-agent:latest" > "$WORK_DIR/image.txt"
  run assert_planner_image "$WORK_DIR/image.txt" "infra-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"infra-agent"* ]]
  [[ "$output" == *"claude-agent"* ]]
}

# ── assert_planner_raw_id ─────────────────────────────────────────────────────

@test "assert_planner_raw_id: passes when raw ID matches expected" {
  echo "python-analysis" > "$WORK_DIR/raw_id.txt"
  run assert_planner_raw_id "$WORK_DIR/raw_id.txt" "python-analysis"
  [ "$status" -eq 0 ]
}

@test "assert_planner_raw_id: passes with default ID" {
  echo "default" > "$WORK_DIR/raw_id.txt"
  run assert_planner_raw_id "$WORK_DIR/raw_id.txt" "default"
  [ "$status" -eq 0 ]
}

@test "assert_planner_raw_id: fails when raw ID does not match" {
  echo "default" > "$WORK_DIR/raw_id.txt"
  run assert_planner_raw_id "$WORK_DIR/raw_id.txt" "infra"
  [ "$status" -ne 0 ]
}

@test "assert_planner_raw_id: fails when file does not exist" {
  run assert_planner_raw_id "$WORK_DIR/nonexistent.txt" "default"
  [ "$status" -ne 0 ]
}

@test "assert_planner_raw_id: failure output mentions expected and actual" {
  echo "default" > "$WORK_DIR/raw_id.txt"
  run assert_planner_raw_id "$WORK_DIR/raw_id.txt" "python-analysis"
  [ "$status" -ne 0 ]
  [[ "$output" == *"python-analysis"* ]]
  [[ "$output" == *"default"* ]]
}

# ── assert_planner_llm_called ─────────────────────────────────────────────────

@test "assert_planner_llm_called: passes when LLM call is recorded" {
  local port=19890
  local response='{"calls":[{"type":"llm","operationName":"selectEnvironment","body":{},"timestamp":"2025-01-01T00:00:00.000Z"}]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys
port   = int(sys.argv[1])
body   = sys.argv[2].encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  local server_pid=$!
  sleep 0.3

  export MOCK_API_URL="http://localhost:${port}"

  run assert_planner_llm_called

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "assert_planner_llm_called: fails when no LLM call is recorded" {
  local port=19891
  local response='{"calls":[{"type":"mutation","operationName":"createComment","body":{},"timestamp":"2025-01-01T00:00:00.000Z"}]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys
port   = int(sys.argv[1])
body   = sys.argv[2].encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  local server_pid=$!
  sleep 0.3

  export MOCK_API_URL="http://localhost:${port}"

  run assert_planner_llm_called

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
}

@test "assert_planner_llm_called: fails when calls array is empty" {
  local port=19892
  local response='{"calls":[]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys
port   = int(sys.argv[1])
body   = sys.argv[2].encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  local server_pid=$!
  sleep 0.3

  export MOCK_API_URL="http://localhost:${port}"

  run assert_planner_llm_called

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
}

# ── assert_planner_llm_not_called ─────────────────────────────────────────────

@test "assert_planner_llm_not_called: passes when no LLM calls recorded" {
  local port=19893
  local response='{"calls":[]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys
port   = int(sys.argv[1])
body   = sys.argv[2].encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  local server_pid=$!
  sleep 0.3

  export MOCK_API_URL="http://localhost:${port}"

  run assert_planner_llm_not_called

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "assert_planner_llm_not_called: fails when LLM calls exist" {
  local port=19894
  local response='{"calls":[{"type":"llm","operationName":"selectEnvironment","body":{},"timestamp":"2025-01-01T00:00:00.000Z"}]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys
port   = int(sys.argv[1])
body   = sys.argv[2].encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  local server_pid=$!
  sleep 0.3

  export MOCK_API_URL="http://localhost:${port}"

  run assert_planner_llm_not_called

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
}
