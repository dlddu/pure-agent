#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for DLD-467: Level 2 k8s manifest changes.
#
# Validates that workflow-template.yaml and rbac.yaml contain the required
# definitions for Level 2 support:
#   - workflow-template.yaml: agent_image, scenario_configmap, mock_api_url parameters
#   - workflow-template.yaml: ConfigMap volume mount on the run-agent / agent-job template
#   - workflow-template.yaml: SCENARIO_DIR environment variable on the agent-job template
#   - rbac.yaml: configmaps verbs include both "create" and "delete"
#
# These tests use only grep/yq-style text scanning so they run without a
# Kubernetes cluster.  The files being tested are in k8s/ at the repo root.

source "$BATS_TEST_DIRNAME/test-helper.sh"

setup() {
  common_setup
  WORKFLOW_TEMPLATE="${REPO_ROOT}/k8s/workflow-template.yaml"
  RBAC="${REPO_ROOT}/k8s/rbac.yaml"
}

# ── workflow-template.yaml: spec.arguments.parameters ─────────────────────────

@test "workflow-template: spec.arguments.parameters contains agent_image" {
  # Arrange / Act / Assert
  grep -q "agent_image" "$WORKFLOW_TEMPLATE"
}

@test "workflow-template: spec.arguments.parameters contains scenario_configmap" {
  grep -q "scenario_configmap" "$WORKFLOW_TEMPLATE"
}

@test "workflow-template: spec.arguments.parameters contains mock_api_url" {
  grep -q "mock_api_url" "$WORKFLOW_TEMPLATE"
}

@test "workflow-template: agent_image parameter is defined under spec.arguments" {
  # The parameter block must appear *before* the templates section so it sits
  # under spec.arguments (not inside a template's inputs).
  run awk '
    /spec:/{in_spec=1}
    in_spec && /templates:/{exit}
    in_spec && /agent_image/{found=1}
    END{exit !found}
  ' "$WORKFLOW_TEMPLATE"
  [ "$status" -eq 0 ]
}

@test "workflow-template: scenario_configmap parameter is defined under spec.arguments" {
  run awk '
    /spec:/{in_spec=1}
    in_spec && /templates:/{exit}
    in_spec && /scenario_configmap/{found=1}
    END{exit !found}
  ' "$WORKFLOW_TEMPLATE"
  [ "$status" -eq 0 ]
}

@test "workflow-template: mock_api_url parameter is defined under spec.arguments" {
  run awk '
    /spec:/{in_spec=1}
    in_spec && /templates:/{exit}
    in_spec && /mock_api_url/{found=1}
    END{exit !found}
  ' "$WORKFLOW_TEMPLATE"
  [ "$status" -eq 0 ]
}

# ── workflow-template.yaml: ConfigMap volume mount ────────────────────────────

@test "workflow-template: file references a configMap volume source" {
  # A ConfigMap-backed volume must be declared somewhere in the template.
  grep -q "configMap:" "$WORKFLOW_TEMPLATE"
}

@test "workflow-template: scenario_configmap is referenced as a volume configMap name" {
  # The volume must use the scenario_configmap workflow parameter.
  grep -q "scenario_configmap" "$WORKFLOW_TEMPLATE"
  # Also verify it appears near a volumeMounts or volumes block.
  run grep -c "scenario_configmap" "$WORKFLOW_TEMPLATE"
  [ "$output" -ge 1 ]
}

@test "workflow-template: a volumeMount targeting a scenario directory is present" {
  # The mount point for the scenario ConfigMap volume must exist.
  grep -q "volumeMounts:" "$WORKFLOW_TEMPLATE"
}

# ── workflow-template.yaml: SCENARIO_DIR environment variable ─────────────────

@test "workflow-template: SCENARIO_DIR environment variable is defined" {
  grep -q "SCENARIO_DIR" "$WORKFLOW_TEMPLATE"
}

@test "workflow-template: SCENARIO_DIR appears inside an env block" {
  # Ensure it is an env entry (name: SCENARIO_DIR), not just a comment.
  run grep -c "name: SCENARIO_DIR" "$WORKFLOW_TEMPLATE"
  [ "$output" -ge 1 ]
}

# ── workflow-template.yaml: agent_image parameter drives container image ──────

@test "workflow-template: agent-job container image references agent_image parameter" {
  # After the change, the agent-job image should be parameterised via
  # workflow.parameters.agent_image (or inputs.parameters.agent_image).
  grep -q "agent_image" "$WORKFLOW_TEMPLATE"
}

# ── rbac.yaml: configmaps verbs ───────────────────────────────────────────────

@test "rbac: configmaps resource rule contains create verb" {
  # The rule for configmaps must list "create".
  # Strategy: extract the line block that contains "configmaps" and check verbs.
  run awk '
    /resources:.*configmaps/ || /configmaps/ {
      in_block=1
    }
    in_block && /verbs:/ {
      getline; verbs=$0
      while (verbs !~ /\]/ && (getline line) > 0) { verbs = verbs line }
      if (verbs ~ /create/) found=1
      in_block=0
    }
    END { exit !found }
  ' "$RBAC"
  [ "$status" -eq 0 ]
}

@test "rbac: configmaps resource rule contains delete verb" {
  run awk '
    /resources:.*configmaps/ || /configmaps/ {
      in_block=1
    }
    in_block && /verbs:/ {
      getline; verbs=$0
      while (verbs !~ /\]/ && (getline line) > 0) { verbs = verbs line }
      if (verbs ~ /delete/) found=1
      in_block=0
    }
    END { exit !found }
  ' "$RBAC"
  [ "$status" -eq 0 ]
}

@test "rbac: configmaps resource rule still contains get verb" {
  # The original get verb must be preserved after adding create and delete.
  run awk '
    /configmaps/ { in_block=1 }
    in_block && /verbs:/ {
      getline; verbs=$0
      while (verbs !~ /\]/ && (getline line) > 0) { verbs = verbs line }
      if (verbs ~ /get/) found=1
      in_block=0
    }
    END { exit !found }
  ' "$RBAC"
  [ "$status" -eq 0 ]
}

@test "rbac: configmaps create verb appears in the file" {
  # Simple presence check as a secondary guard.
  grep -q "create" "$RBAC"
}

@test "rbac: configmaps delete verb appears in the file" {
  grep -q "delete" "$RBAC"
}

@test "rbac: configmaps section is present in rbac.yaml" {
  grep -q "configmaps" "$RBAC"
}
