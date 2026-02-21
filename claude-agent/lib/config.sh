#!/bin/bash
# Backward-compatible facade — sources the split config modules.
# Prefer sourcing lib/validate.sh, lib/mcp-config.sh, lib/prompt.sh directly.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, constants.sh

_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CONFIG_DIR/validate.sh"
source "$_CONFIG_DIR/mcp-config.sh"
source "$_CONFIG_DIR/prompt.sh"
unset _CONFIG_DIR
