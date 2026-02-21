#!/bin/bash
# Shared default values used by both lib/constants.sh and hooks/lib.sh.
# This file exists to eliminate duplication of the WORK_DIR default.
# Keep this file minimal — only values needed by both contexts.

# shellcheck disable=SC2034  # Sourced by lib/constants.sh and hooks/lib.sh
DEFAULT_WORK_DIR="/work"
