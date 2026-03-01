#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/lib/runner.sh

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  load_runner
}

# ── YAML parsing: scenario metadata ──────────────────────────────────────────

@test "parse_scenario: extracts name from scenario YAML" {
  # Arrange
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: happy-path
level: unit
fixtures: {}
assertions: []
YAML

  # Act
  run parse_scenario_field "$yaml_file" ".name"

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "happy-path" ]
}

@test "parse_scenario: extracts level from scenario YAML" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: depth-limit
level: integration
fixtures: {}
assertions: []
YAML

  run parse_scenario_field "$yaml_file" ".level"

  [ "$status" -eq 0 ]
  [ "$output" = "integration" ]
}

@test "parse_scenario: fails when YAML file does not exist" {
  run parse_scenario_field "$FIXTURE_DIR/nonexistent.yaml" ".name"
  [ "$status" -ne 0 ]
}

# ── Fixture placement ─────────────────────────────────────────────────────────

@test "place_fixtures: copies export_config.json to SCENARIO_DIR" {
  # Arrange
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  local fixture_src="$FIXTURE_DIR/export_config.json"
  echo '{"action":"none"}' > "$fixture_src"
  cat > "$yaml_file" <<YAML
name: test
level: unit
fixtures:
  export_config: "${fixture_src}"
assertions: []
YAML

  local target_dir="$BATS_TEST_TMPDIR/scenario_out"
  mkdir -p "$target_dir"

  # Act
  run place_fixtures "$yaml_file" "$target_dir"

  # Assert
  [ "$status" -eq 0 ]
  [ -f "$target_dir/export_config.json" ]
}

@test "place_fixtures: copied export_config.json preserves content" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  local fixture_src="$FIXTURE_DIR/export_config.json"
  local expected='{"action":"create_pr"}'
  echo "$expected" > "$fixture_src"
  cat > "$yaml_file" <<YAML
name: test
level: unit
fixtures:
  export_config: "${fixture_src}"
assertions: []
YAML

  local target_dir="$BATS_TEST_TMPDIR/scenario_out"
  mkdir -p "$target_dir"

  place_fixtures "$yaml_file" "$target_dir"

  local actual
  actual=$(cat "$target_dir/export_config.json")
  [ "$actual" = "$expected" ]
}

@test "place_fixtures: copies agent_result.txt to SCENARIO_DIR when present" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  local fixture_src="$FIXTURE_DIR/agent_result.txt"
  echo "Task done." > "$fixture_src"
  cat > "$yaml_file" <<YAML
name: test
level: unit
fixtures:
  agent_result: "${fixture_src}"
assertions: []
YAML

  local target_dir="$BATS_TEST_TMPDIR/scenario_out"
  mkdir -p "$target_dir"

  run place_fixtures "$yaml_file" "$target_dir"

  [ "$status" -eq 0 ]
  [ -f "$target_dir/agent_result.txt" ]
}

@test "place_fixtures: succeeds when fixtures section is empty" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: depth-limit
level: unit
fixtures: {}
assertions: []
YAML

  local target_dir="$BATS_TEST_TMPDIR/scenario_out"
  mkdir -p "$target_dir"

  run place_fixtures "$yaml_file" "$target_dir"
  [ "$status" -eq 0 ]
}

# ── SCENARIO_DIR env variable ─────────────────────────────────────────────────

@test "setup_scenario_env: exports SCENARIO_DIR to the target directory path" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: env-test
level: unit
fixtures: {}
assertions: []
YAML

  local target_dir="$BATS_TEST_TMPDIR/scenario_env"
  mkdir -p "$target_dir"

  # Act
  run bash -c "
    source '$LIB_DIR/runner.sh' --source-only
    setup_scenario_env '$target_dir'
    echo \"\$SCENARIO_DIR\"
  "

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "$target_dir" ]
}

# ── Scenario assertions format ────────────────────────────────────────────────

@test "parse_scenario: scenario YAML with assertions array is valid" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: pr-creation
level: integration
fixtures: {}
assertions:
  - type: router_decision
    expected: assign
  - type: exit_code
    expected: 0
YAML

  run parse_scenario_field "$yaml_file" ".assertions | length"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_scenario: each assertion entry has a type field" {
  local yaml_file="$FIXTURE_DIR/scenario.yaml"
  cat > "$yaml_file" <<'YAML'
name: pr-creation
level: integration
fixtures: {}
assertions:
  - type: router_decision
    expected: assign
YAML

  run parse_scenario_field "$yaml_file" ".assertions[0].type"
  [ "$status" -eq 0 ]
  [ "$output" = "router_decision" ]
}
