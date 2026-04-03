#!/bin/bash
# System prompt construction for planner.
# NOTE: This file is sourced by entrypoint.sh which sets -euo pipefail.
# Depends on: logging.sh, environments.sh

# Build the full prompt combining system instructions and user task.
# Outputs the combined prompt to stdout.
build_prompt() {
  local task_prompt="$PROMPT"
  local env_descriptions
  env_descriptions="$(_environment_descriptions)"

  cat << EOF
You are a routing assistant that selects the best execution environment for an AI agent task.

Available environments:
${env_descriptions}

Analyze the task description and select the most appropriate environment.

Selection guidelines:
- "default": General coding, code review, documentation, git operations
- "python-analysis": Data analysis, visualization, pandas/numpy, ML/AI
- "infra": Kubernetes, infrastructure, kubectl, Helm, AWS/cloud, deploy

If the task prompt contains a Linear issue ID (e.g. DLD-123, PROJ-456), use the get_issue tool to read the issue details before making your decision.

After analysis, respond with ONLY a JSON object: {"environment_id": "<id>"}

If uncertain, choose "default".

---
Task:
${task_prompt}
EOF
}
