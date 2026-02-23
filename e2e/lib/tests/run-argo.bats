#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for e2e/run-argo.sh — patch_workflow_template_for_mock()
#
# 검증 범위:
#   1. agent-job 컨테이너에 SCENARIO_DIR 환경변수가 추가되는지
#   2. agent-job 컨테이너에 scenario-data 볼륨마운트가 추가되는지
#   3. run-cycle 템플릿에 scenario-data 볼륨(ConfigMap 참조)이 추가되는지
#   4. 기존 mock 이미지 패치(agent-job, mcp-daemon, llm-gateway-daemon)가 올바른지
#
# 전제:
#   - yq (mikefarah/yq v4+) 가 PATH에 있어야 합니다.
#   - kind 클러스터, Argo Workflows, kubectl 없이 단독 실행 가능합니다.

source "$BATS_TEST_DIRNAME/test-helper.sh"

# ── 테스트 공통 설정 ──────────────────────────────────────────────────────────

# RUN_ARGO_SH: 프로젝트 루트 기준 절대 경로
RUN_ARGO_SH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/e2e/run-argo.sh"
WORKFLOW_TEMPLATE_SRC="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/k8s/workflow-template.yaml"

setup() {
  common_setup

  # patch_workflow_template_for_mock()이 필요로 하는 환경 변수
  export LEVEL=2
  export SCENARIO=all
  export NAMESPACE=pure-agent
  export KUBE_CONTEXT=kind-pure-agent-e2e
  export MOCK_AGENT_IMAGE="pure-agent/mock-agent:e2e"
  export MOCK_API_IMAGE="pure-agent/mock-api:e2e"
  # Level 3 전용 변수 — 더미 값으로 설정 (Level 2에서는 사용하지 않음)
  export GITHUB_TEST_REPO="mock-org/mock-repo"

  # 패치 결과를 저장할 임시 파일
  PATCHED_YAML="$BATS_TEST_TMPDIR/workflow-template-patched.yaml"
  export PATCHED_YAML

  # run-argo.sh 함수를 로드
  # shellcheck disable=SC1090
  source "$RUN_ARGO_SH" --source-only

  # 원본 WorkflowTemplate을 임시 파일로 복사하여 patch 적용
  patch_workflow_template_for_mock \
    "$WORKFLOW_TEMPLATE_SRC" \
    "$PATCHED_YAML" \
    "test-scenario"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. SCENARIO_DIR 환경변수 주입
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch_workflow_template_for_mock: agent-job 컨테이너 env에 SCENARIO_DIR가 존재한다" {
  # Act: 패치된 YAML에서 agent-job 템플릿의 env 이름 목록 추출
  run yq eval \
    '[.spec.templates[] | select(.name == "agent-job") | .container.env[].name] | .[]' \
    "$PATCHED_YAML"

  # Assert: SCENARIO_DIR 항목이 env 목록에 포함되어야 한다
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCENARIO_DIR"* ]]
}

@test "patch_workflow_template_for_mock: agent-job의 SCENARIO_DIR 값이 /scenario이다" {
  # Act: SCENARIO_DIR env 항목의 value를 추출
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.env[] | select(.name == "SCENARIO_DIR") | .value' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "/scenario" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. scenario-data 볼륨마운트 주입 (agent-job)
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch_workflow_template_for_mock: agent-job의 volumeMounts에 scenario-data가 존재한다" {
  # Act: agent-job 컨테이너의 volumeMount 이름 목록 추출
  run yq eval \
    '[.spec.templates[] | select(.name == "agent-job") | .container.volumeMounts[].name] | .[]' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"scenario-data"* ]]
}

@test "patch_workflow_template_for_mock: agent-job의 scenario-data 마운트 경로가 /scenario이다" {
  # Act: scenario-data 볼륨마운트의 mountPath 추출
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.volumeMounts[] | select(.name == "scenario-data") | .mountPath' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "/scenario" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. scenario-data 볼륨 주입 (run-cycle 템플릿)
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch_workflow_template_for_mock: run-cycle 템플릿에 volumes 섹션이 존재한다" {
  # Act: run-cycle 템플릿의 volumes 배열 길이 확인
  run yq eval \
    '.spec.templates[] | select(.name == "run-cycle") | .volumes | length' \
    "$PATCHED_YAML"

  # Assert: 볼륨이 최소 1개 이상 존재해야 한다
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "patch_workflow_template_for_mock: run-cycle 템플릿의 volumes에 scenario-data가 존재한다" {
  # Act: run-cycle 볼륨 이름 목록 추출
  run yq eval \
    '[.spec.templates[] | select(.name == "run-cycle") | .volumes[].name] | .[]' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"scenario-data"* ]]
}

@test "patch_workflow_template_for_mock: run-cycle의 scenario-data 볼륨이 configMap 참조를 가진다" {
  # Act: scenario-data 볼륨의 configMap 필드가 null이 아닌지 확인
  run yq eval \
    '.spec.templates[] | select(.name == "run-cycle") | .volumes[] | select(.name == "scenario-data") | .configMap' \
    "$PATCHED_YAML"

  # Assert: configMap 필드가 존재하고 비어 있지 않아야 한다
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "null" ]
}

@test "patch_workflow_template_for_mock: run-cycle의 scenario-data configMap이 name 필드를 가진다" {
  # Act: configMap.name 필드 추출
  run yq eval \
    '.spec.templates[] | select(.name == "run-cycle") | .volumes[] | select(.name == "scenario-data") | .configMap.name' \
    "$PATCHED_YAML"

  # Assert: configMap.name이 null이 아니고 비어 있지 않아야 한다
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "null" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. 기존 mock 이미지 패치 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch_workflow_template_for_mock: agent-job 이미지가 MOCK_AGENT_IMAGE로 교체된다" {
  # Act: agent-job 컨테이너 이미지 추출
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.image' \
    "$PATCHED_YAML"

  # Assert: MOCK_AGENT_IMAGE 값과 일치해야 한다
  [ "$status" -eq 0 ]
  [ "$output" = "$MOCK_AGENT_IMAGE" ]
}

@test "patch_workflow_template_for_mock: agent-job 이미지가 원본 claude-agent 이미지가 아니다" {
  # Act
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.image' \
    "$PATCHED_YAML"

  # Assert: 원본 이미지(ghcr.io/.../claude-agent)가 남아있으면 안 된다
  [ "$status" -eq 0 ]
  [[ "$output" != *"claude-agent"* ]]
}

@test "patch_workflow_template_for_mock: mcp-daemon 이미지가 MOCK_API_IMAGE로 교체된다" {
  # Act: mcp-daemon 컨테이너 이미지 추출
  run yq eval \
    '.spec.templates[] | select(.name == "mcp-daemon") | .container.image' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [ "$output" = "$MOCK_API_IMAGE" ]
}

@test "patch_workflow_template_for_mock: llm-gateway-daemon 이미지가 busybox로 교체된다" {
  # Act: llm-gateway-daemon 컨테이너 이미지 추출
  run yq eval \
    '.spec.templates[] | select(.name == "llm-gateway-daemon") | .container.image' \
    "$PATCHED_YAML"

  # Assert: busybox 이미지를 사용해야 한다
  [ "$status" -eq 0 ]
  [[ "$output" == *"busybox"* ]]
}

@test "patch_workflow_template_for_mock: agent-job의 entrypoint가 /app/entrypoint.sh로 설정된다" {
  # mock-agent의 entrypoint가 올바르게 주입되었는지 확인
  # Act
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.command | .[]' \
    "$PATCHED_YAML"

  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"/app/entrypoint.sh"* ]]
}

@test "patch_workflow_template_for_mock: 패치 후 imagePullPolicy가 IfNotPresent로 설정된다" {
  # kind 클러스터에서 로컬 이미지를 사용하기 위한 패치 확인
  # agent-job의 imagePullPolicy를 확인 (컨테이너가 있는 템플릿 중 하나)
  run yq eval \
    '.spec.templates[] | select(.name == "agent-job") | .container.imagePullPolicy' \
    "$PATCHED_YAML"

  [ "$status" -eq 0 ]
  [ "$output" = "IfNotPresent" ]
}
