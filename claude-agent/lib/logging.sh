#!/bin/bash
# Logging utilities for claude-agent entrypoint.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.

log()  { echo "[entrypoint] $*" >&2; }
warn() { echo "[entrypoint] WARN: $*" >&2; }
die()  { echo "[entrypoint] ERROR: $*" >&2; exit 1; }
