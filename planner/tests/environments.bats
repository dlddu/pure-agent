#!/usr/bin/env bats
# Tests for lib/environments.sh: resolve_image

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
}

_load() { _load_lib logging constants environments; }

# ── resolve_image ────────────────────────────────────────────

@test "resolve_image: default returns claude-agent image" {
  _load
  result=$(resolve_image "default")
  [[ "$result" == *"claude-agent"* ]]
}

@test "resolve_image: python-analysis returns python-agent image" {
  _load
  result=$(resolve_image "python-analysis")
  [[ "$result" == *"python-agent"* ]]
}

@test "resolve_image: infra returns infra-agent image" {
  _load
  result=$(resolve_image "infra")
  [[ "$result" == *"infra-agent"* ]]
}

@test "resolve_image: unknown ID returns default image" {
  _load
  result=$(resolve_image "nonexistent")
  [[ "$result" == *"claude-agent"* ]]
}

@test "resolve_image: empty string returns default image" {
  _load
  result=$(resolve_image "")
  [[ "$result" == *"claude-agent"* ]]
}

@test "resolve_image: no argument returns default image" {
  _load
  result=$(resolve_image)
  [[ "$result" == *"claude-agent"* ]]
}

# ── _environment_descriptions ────────────────────────────────

@test "_environment_descriptions: contains all three environments" {
  _load
  result=$(_environment_descriptions)
  [[ "$result" == *"default"* ]]
  [[ "$result" == *"python-analysis"* ]]
  [[ "$result" == *"infra"* ]]
}
