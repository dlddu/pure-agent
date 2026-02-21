#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for Claude Code stop hooks

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

# ── lib.sh: hook_read_input ──────────────────────────────────

@test "hook_read_input: sets HOOK_INPUT from valid JSON stdin" {
  result=$(echo '{"stop_hook_active":false}' | _run_hook_lib "hook_read_input; echo \"\$HOOK_INPUT\"")
  [[ "$result" == *"stop_hook_active"* ]]
}

@test "hook_read_input: exits 0 on empty stdin (fail-open)" {
  run _run_hook_lib "echo '' | hook_read_input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing stop"* ]]
}

@test "hook_read_input: exits 0 on invalid JSON (fail-open)" {
  run _run_hook_lib "echo 'not json' | hook_read_input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing stop"* ]]
}

# ── lib.sh: hook_is_bypass_active ────────────────────────────

@test "hook_is_bypass_active: returns true when flag is set" {
  run _run_hook_lib "
    HOOK_INPUT='{\"stop_hook_active\":true}'
    hook_is_bypass_active && echo 'bypassed' || echo 'not bypassed'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"bypassed"* ]]
}

@test "hook_is_bypass_active: returns false when flag is not set" {
  run _run_hook_lib "
    HOOK_INPUT='{\"stop_hook_active\":false}'
    hook_is_bypass_active && echo 'bypassed' || echo 'not bypassed'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"not bypassed"* ]]
}

@test "hook_is_bypass_active: returns false when key is missing" {
  run _run_hook_lib "
    HOOK_INPUT='{}'
    hook_is_bypass_active && echo 'bypassed' || echo 'not bypassed'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"not bypassed"* ]]
}

# ── lib.sh: hook_file_exists ─────────────────────────────────

@test "hook_file_exists: returns true when file exists" {
  touch "$WORK_DIR/test_file"
  run _run_hook_lib "hook_file_exists 'test_file' && echo 'exists' || echo 'missing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists"* ]]
}

@test "hook_file_exists: returns false when file is missing" {
  run _run_hook_lib "hook_file_exists 'nonexistent' && echo 'exists' || echo 'missing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing"* ]]
}

@test "hook_file_exists: returns false with empty argument" {
  run _run_hook_lib "hook_file_exists '' && echo 'exists' || echo 'missing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing"* ]]
}

# ── lib.sh: hook_block ──────────────────────────────────────

@test "hook_block: exits 2 with message argument" {
  run _run_hook_lib "hook_block 'must complete export'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must complete export"* ]]
}

@test "hook_block: exits 2 with heredoc input" {
  run _run_hook_lib "
    hook_block <<'INNER_EOF'
block message here
INNER_EOF
  "
  [ "$status" -eq 2 ]
  [[ "$output" == *"block message here"* ]]
}

# ── lib.sh: hook_run ────────────────────────────────────────

@test "hook_run: calls provided function after reading input" {
  run _run_hook_lib "
    my_hook() { echo 'hook called' >&2; exit 0; }
    echo '{\"stop_hook_active\":false}' | hook_run my_hook
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook called"* ]]
}

@test "hook_run: skips function when bypass active" {
  run _run_hook_lib "
    my_hook() { echo 'should not run' >&2; exit 2; }
    echo '{\"stop_hook_active\":true}' | hook_run my_hook
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"should not run"* ]]
}

@test "hook_run: fails with no function argument" {
  run -127 _run_hook_lib "echo '{}' | hook_run"
  [ "$status" -ne 0 ]
}

# ── ensure-export-config.sh ─────────────────────────────────

@test "ensure-export-config: passes when export_config.json exists" {
  touch "$WORK_DIR/export_config.json"
  run _run_hook_script ensure-export-config.sh false
  [ "$status" -eq 0 ]
}

@test "ensure-export-config: blocks when export_config.json is missing" {
  run _run_hook_script ensure-export-config.sh false
  [ "$status" -eq 2 ]
  [[ "$output" == *"set_export_config"* ]]
}

@test "ensure-export-config: passes with bypass active" {
  run _run_hook_script ensure-export-config.sh true
  [ "$status" -eq 0 ]
}

@test "ensure-export-config: fails open on empty stdin" {
  run _run_hook_script ensure-export-config.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing stop"* ]]
}

# ── feature-request-review.sh ───────────────────────────────

@test "feature-request-review: blocks on first run" {
  run _run_hook_script feature-request-review.sh false
  [ "$status" -eq 2 ]
  [[ "$output" == *"request_feature"* ]]
}

@test "feature-request-review: creates flag file on first run" {
  _run_hook_script feature-request-review.sh false 2>/dev/null || true
  [ -f "$WORK_DIR/.feature_review_done" ]
}

@test "feature-request-review: passes on second run (flag file exists)" {
  touch "$WORK_DIR/.feature_review_done"
  run _run_hook_script feature-request-review.sh false
  [ "$status" -eq 0 ]
}

@test "feature-request-review: passes with bypass active" {
  run _run_hook_script feature-request-review.sh true
  [ "$status" -eq 0 ]
}
