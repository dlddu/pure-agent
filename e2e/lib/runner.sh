#!/usr/bin/env bash
# e2e/lib/runner.sh — scenario runner helpers for e2e tests.
#
# Usage in BATS: source this file with --source-only to load functions only.
#
# Functions:
#   parse_scenario_field <yaml_file> <jq_path>  — extract a field via yq
#   place_fixtures <yaml_file> <target_dir>      — copy fixtures to target_dir
#   setup_scenario_env <target_dir>              — export SCENARIO_DIR
#
# Requires: yq (YAML processor with jq filter support), jq

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  true
fi

# ── parse_scenario_field ──────────────────────────────────────────────────────
# Extract a field from a scenario YAML file using yq.
# yq automatically converts YAML to JSON and applies the jq filter.
#
# Usage:
#   parse_scenario_field scenario.yaml ".name"

parse_scenario_field() {
  local yaml_file="$1"
  local jq_path="$2"

  if [ ! -f "$yaml_file" ]; then
    echo "runner.sh: YAML file not found: '$yaml_file'" >&2
    return 1
  fi

  yq eval "$jq_path" "$yaml_file"
}

# ── place_fixtures ────────────────────────────────────────────────────────────
# Read fixture paths from a scenario YAML and copy them into target_dir.
# Fixture keys are mapped to their canonical filenames:
#   fixtures.export_config  → export_config.json
#   fixtures.agent_result   → agent_result.txt
#
# Unknown or absent fixture keys are silently ignored (supports depth-limit).

place_fixtures() {
  local yaml_file="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"

  # export_config
  local export_config_src
  export_config_src=$(yq eval '.fixtures.export_config // ""' "$yaml_file")
  if [ -n "$export_config_src" ] && [ "$export_config_src" != "null" ] && [ -f "$export_config_src" ]; then
    cp "$export_config_src" "$target_dir/export_config.json"
  fi

  # agent_result
  local agent_result_src
  agent_result_src=$(yq eval '.fixtures.agent_result // ""' "$yaml_file")
  if [ -n "$agent_result_src" ] && [ "$agent_result_src" != "null" ] && [ -f "$agent_result_src" ]; then
    cp "$agent_result_src" "$target_dir/agent_result.txt"
  fi
}

# ── setup_scenario_env ────────────────────────────────────────────────────────
# Export SCENARIO_DIR so that mock-agent and other components can find fixtures.

setup_scenario_env() {
  local target_dir="$1"
  export SCENARIO_DIR="$target_dir"
}
