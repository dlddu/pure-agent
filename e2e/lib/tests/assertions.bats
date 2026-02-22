#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/assertions.sh

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_assertions
}

# ── assert_exit_code ──────────────────────────────────────────────────────────

@test "assert_exit_code: passes when expected equals actual" {
  run assert_exit_code 0 0
  [ "$status" -eq 0 ]
}

@test "assert_exit_code: passes when non-zero expected equals actual" {
  run assert_exit_code 1 1
  [ "$status" -eq 0 ]
}

@test "assert_exit_code: fails when expected does not match actual" {
  run assert_exit_code 0 1
  [ "$status" -ne 0 ]
}

@test "assert_exit_code: failure output mentions expected and actual values" {
  run assert_exit_code 0 2
  [[ "$output" == *"0"* ]]
  [[ "$output" == *"2"* ]]
}

# ── assert_file_exists ────────────────────────────────────────────────────────

@test "assert_file_exists: passes when the file is present" {
  touch "$WORK_DIR/present.txt"
  run assert_file_exists "$WORK_DIR/present.txt"
  [ "$status" -eq 0 ]
}

@test "assert_file_exists: fails when the file is absent" {
  run assert_file_exists "$WORK_DIR/absent.txt"
  [ "$status" -ne 0 ]
}

@test "assert_file_exists: failure output mentions the missing path" {
  run assert_file_exists "$WORK_DIR/missing.txt"
  [[ "$output" == *"missing.txt"* ]]
}

# ── assert_file_contains ──────────────────────────────────────────────────────

@test "assert_file_contains: passes when expected string is present in file" {
  echo "hello world" > "$WORK_DIR/file.txt"
  run assert_file_contains "$WORK_DIR/file.txt" "hello"
  [ "$status" -eq 0 ]
}

@test "assert_file_contains: passes when expected string is an exact full-line match" {
  echo "exact line" > "$WORK_DIR/file.txt"
  run assert_file_contains "$WORK_DIR/file.txt" "exact line"
  [ "$status" -eq 0 ]
}

@test "assert_file_contains: fails when expected string is absent" {
  echo "hello world" > "$WORK_DIR/file.txt"
  run assert_file_contains "$WORK_DIR/file.txt" "not present"
  [ "$status" -ne 0 ]
}

@test "assert_file_contains: fails when file does not exist" {
  run assert_file_contains "$WORK_DIR/nonexistent.txt" "anything"
  [ "$status" -ne 0 ]
}

@test "assert_file_contains: failure output mentions the expected string" {
  echo "other content" > "$WORK_DIR/file.txt"
  run assert_file_contains "$WORK_DIR/file.txt" "expected-string"
  [[ "$output" == *"expected-string"* ]]
}

# ── assert_router_decision ────────────────────────────────────────────────────

@test "assert_router_decision: passes when router output file contains the expected decision" {
  # Arrange — write a fake router output file
  local router_output="$WORK_DIR/router_decision.txt"
  echo "assign" > "$router_output"
  export ROUTER_OUTPUT="$router_output"

  run assert_router_decision "assign"
  [ "$status" -eq 0 ]
}

@test "assert_router_decision: fails when router output contains a different decision" {
  local router_output="$WORK_DIR/router_decision.txt"
  echo "skip" > "$router_output"
  export ROUTER_OUTPUT="$router_output"

  run assert_router_decision "assign"
  [ "$status" -ne 0 ]
}

@test "assert_router_decision: fails when router output file is missing" {
  export ROUTER_OUTPUT="$WORK_DIR/nonexistent_decision.txt"

  run assert_router_decision "assign"
  [ "$status" -ne 0 ]
}

@test "assert_router_decision: failure output mentions expected and actual decision" {
  local router_output="$WORK_DIR/router_decision.txt"
  echo "skip" > "$router_output"
  export ROUTER_OUTPUT="$router_output"

  run assert_router_decision "assign"
  [[ "$output" == *"assign"* ]]
  [[ "$output" == *"skip"* ]]
}

# ── assert_mock_api ───────────────────────────────────────────────────────────
# assert_mock_api queries GET /assertions on the running mock-api server.
# We simulate the server response by setting MOCK_API_URL to a local netcat
# listener or by using a minimal fake server started inline.

@test "assert_mock_api: passes when a matching mutation exists in recorded calls" {
  # Arrange — spin up a minimal Python HTTP server that serves a canned response
  local port=19876
  local response='{"calls":[{"type":"mutation","operationName":"createComment","body":{"issueId":"issue-1"},"timestamp":"2025-01-01T00:00:00.000Z"}]}'

  python3 - "$port" "$response" <<'PYEOF' &
import http.server, sys, json
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

  # Act
  run assert_mock_api "mutation" "createComment"

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "assert_mock_api: fails when no matching call exists" {
  # Arrange — server returns empty calls
  local port=19877
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

  # Act
  run assert_mock_api "mutation" "createComment"

  kill "$server_pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
}
