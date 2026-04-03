#!/bin/bash
# Agent execution environments: image registry and lookup.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: constants.sh
#
# Keep in sync with mcp-server environment-constants.ts

# Resolve an environment ID to its container image.
# Falls back to DEFAULT_IMAGE for unknown or empty IDs.
# Args: $1 = environment_id (may be empty)
# Outputs: container image string to stdout
resolve_image() {
  local env_id="${1:-}"
  case "$env_id" in
    default)           echo "ghcr.io/dlddu/pure-agent/claude-agent:latest" ;;
    python-analysis)   echo "ghcr.io/dlddu/pure-agent/python-agent:latest" ;;
    infra)             echo "ghcr.io/dlddu/pure-agent/infra-agent:latest" ;;
    *)                 echo "$DEFAULT_IMAGE" ;;
  esac
}

# Environment descriptions for the system prompt.
# Used by lib/prompt.sh to build the routing prompt.
# Outputs: multi-line environment descriptions to stdout
_environment_descriptions() {
  cat << 'EOF'
- id: "default" | 기본 환경. Claude Code CLI, git, curl, jq 포함. 일반적인 코딩 작업에 적합. | capabilities: [claude-code, git, shell]
- id: "python-analysis" | Python 분석 환경. pandas, numpy, matplotlib 등 데이터 분석 도구 포함. | capabilities: [python, pip, data-analysis, git, shell]
- id: "infra" | 인프라 환경. kubectl, helm, AWS CLI 등 인프라 관리 도구 포함. | capabilities: [kubectl, helm, aws-cli, git, shell]
EOF
}
