#!/bin/bash
# Logging utilities for planner entrypoint.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.

log()  { echo "[planner] $*" >&2; }
warn() { echo "[planner] WARN: $*" >&2; }
die()  { echo "[planner] ERROR: $*" >&2; exit 1; }
