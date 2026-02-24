#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# e2e/lib/tests/patch-workflow-mock-gh.bats
#
# DLD-467: patch_workflow_template_for_mock의 mock-gh 주입 로직 검증 테스트
#
# run-argo.sh의 patch_workflow_template_for_mock 함수가 WorkflowTemplate에
# mock-gh 관련 설정을 올바르게 주입하는지 검증합니다.
#
# 검증 항목:
#   1. 패치 후 YAML에 mock-gh 볼륨(ConfigMap 또는 emptyDir)이 추가되는지
#   2. export-handler 컨테이너에 mock-gh 볼륨 마운트가 추가되는지
#   3. 패치된 YAML이 유효한 Kubernetes/Argo 리소스인지
#   4. 기존 패치(storageClassName, imagePullPolicy 등)가 함께 적용되는지
#
# 전제:
#   - yq (v4+) CLI가 PATH에 있어야 합니다.
#   - run-argo.sh --source-only로 로드 가능해야 합니다.
#
# 실행 방법:
#   bats e2e/lib/tests/patch-workflow-mock-gh.bats

source "$BATS_TEST_DIRNAME/test-helper.sh"

# ── 공통 설정 ───────────────────────────────────────────────────────────────

setup() {
  common_setup

  # 경로 정의
  E2E_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REPO_DIR="$(cd "$E2E_DIR/.." && pwd)"
  export E2E_DIR REPO_DIR

  SRC_TEMPLATE="$REPO_DIR/k8s/workflow-template.yaml"
  export SRC_TEMPLATE

  # 각 테스트가 독립적인 출력 파일을 사용합니다.
  DST_TEMPLATE="$BATS_TEST_TMPDIR/workflow-template-patched.yaml"
  export DST_TEMPLATE

  # yq가 PATH에 있는지 확인합니다.
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq CLI가 PATH에 없습니다 — yq v4 이상 설치 필요"
  fi

  # run-argo.sh를 --source-only 모드로 로드합니다.
  # Level/Scenario 기본값을 설정하여 실행되지 않도록 합니다.
  export LEVEL=2
  export SCENARIO=all
  export NAMESPACE=pure-agent
  export KUBE_CONTEXT=kind-pure-agent-e2e
  export MOCK_AGENT_IMAGE="pure-agent/mock-agent:e2e"
  export MOCK_API_IMAGE="pure-agent/mock-api:e2e"
  export MOCK_GH_IMAGE="${MOCK_GH_IMAGE:-pure-agent/mock-gh:e2e}"
  export GITHUB_TEST_REPO="mock-org/mock-repo"

  # shellcheck disable=SC1090
  source "$E2E_DIR/run-argo.sh" --source-only
}

# ── 헬퍼: patch_workflow_template_for_mock 실행 ─────────────────────────────

run_patch() {
  patch_workflow_template_for_mock \
    "$SRC_TEMPLATE" \
    "$DST_TEMPLATE" \
    "test-scenario"
}

# ── 헬퍼: yq로 패치된 YAML에서 값 추출 ──────────────────────────────────────

yaml_get_patched() {
  local path="$1"
  yq eval "$path" "$DST_TEMPLATE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. 기존 패치가 함께 적용되는지 검증 (회귀 테스트)
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: 원본 WorkflowTemplate 파일이 존재한다" {
  [ -f "$SRC_TEMPLATE" ]
}

@test "patch: 패치 후 출력 YAML 파일이 생성된다" {
  run_patch
  [ -f "$DST_TEMPLATE" ]
}

@test "patch: storageClassName이 efs에서 standard로 변경된다" {
  run_patch

  # kind local-path provisioner 호환성: efs → standard
  local storage_class
  storage_class=$(yaml_get_patched \
    '.spec.volumeClaimTemplates[0].spec.storageClassName')
  [ "$storage_class" = "standard" ]
}

@test "patch: accessModes가 ReadWriteMany에서 ReadWriteOnce로 변경된다" {
  run_patch

  local access_mode
  access_mode=$(yaml_get_patched \
    '.spec.volumeClaimTemplates[0].spec.accessModes[0]')
  [ "$access_mode" = "ReadWriteOnce" ]
}

@test "patch: agent-job 컨테이너 이미지가 MOCK_AGENT_IMAGE로 교체된다" {
  run_patch

  local agent_image
  agent_image=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "agent-job") | .container.image)')
  [ "$agent_image" = "$MOCK_AGENT_IMAGE" ]
}

@test "patch: mcp-daemon 컨테이너 이미지가 MOCK_API_IMAGE로 교체된다" {
  run_patch

  local mcp_image
  mcp_image=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "mcp-daemon") | .container.image)')
  [ "$mcp_image" = "$MOCK_API_IMAGE" ]
}

@test "patch: llm-gateway-daemon 컨테이너 이미지가 busybox로 교체된다" {
  run_patch

  local llm_image
  llm_image=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "llm-gateway-daemon") | .container.image)')
  [[ "$llm_image" == *"busybox"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. mock-gh 볼륨 주입 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: 패치 후 YAML에 mock-gh 관련 볼륨 설정이 존재한다" {
  # mock-gh는 ConfigMap 볼륨 또는 emptyDir + initContainer로 주입됩니다.
  # 패치된 YAML에서 mock-gh 관련 볼륨 이름이 존재해야 합니다.
  run_patch

  local yaml_content
  yaml_content=$(cat "$DST_TEMPLATE")

  # mock-gh 볼륨 이름이 포함되어 있어야 합니다.
  [[ "$yaml_content" == *"mock-gh"* ]]
}

@test "patch: export-handler 템플릿에 mock-gh 볼륨 마운트가 추가된다" {
  # export-handler(export-cycle-output 템플릿)가 mock-gh 볼륨을 마운트해야 합니다.
  # volumeMounts 배열에 mock-gh 관련 항목이 있어야 합니다.
  run_patch

  local mount_count
  mount_count=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output") | .container.volumeMounts[] | select(.name | test("mock-gh"))) | length')

  # mock-gh 볼륨 마운트가 1개 이상 존재해야 합니다.
  [ "$mount_count" -ge 1 ]
}

@test "patch: export-handler의 mock-gh 볼륨 마운트 경로가 /usr/local/bin/gh이다" {
  # mock-gh는 실제 gh CLI를 덮어쓰기 위해 /usr/local/bin/gh에 마운트됩니다.
  run_patch

  local mount_path
  mount_path=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output")
      | .container.volumeMounts[]
      | select(.name | test("mock-gh"))
      | .mountPath)')

  [ "$mount_path" = "/usr/local/bin/gh" ]
}

@test "patch: mock-gh 볼륨이 export-handler 템플릿 수준의 volumes에 정의된다" {
  # export-cycle-output 템플릿에 mock-gh 볼륨이 volumes 배열에 정의되어야 합니다.
  # (ConfigMap 볼륨 또는 initContainer용 emptyDir 볼륨)
  run_patch

  local volume_name
  volume_name=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output")
      | .volumes[]
      | select(.name | test("mock-gh"))
      | .name)')

  [ -n "$volume_name" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. mock-gh 주입 방법별 세부 검증
#    ConfigMap 방식 OR initContainer 방식 중 하나를 검증합니다.
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: mock-gh 볼륨이 ConfigMap 참조 또는 emptyDir로 정의된다" {
  # mock-gh 주입은 두 가지 방법 중 하나를 사용합니다:
  #   A. ConfigMap 방식: mock-gh 스크립트를 ConfigMap으로 생성하고 volumeMount
  #   B. initContainer 방식: mock-gh 이미지에서 emptyDir로 파일 복사
  run_patch

  local yaml_content
  yaml_content=$(cat "$DST_TEMPLATE")

  # ConfigMap 이름(mock-gh) 또는 emptyDir이 포함되어야 합니다.
  [[ "$yaml_content" == *"configMap"*"mock-gh"* ]] \
    || [[ "$yaml_content" == *"emptyDir"* ]]
}

@test "patch: subPath를 사용하여 gh 바이너리만 마운트한다" {
  # /usr/local/bin/gh 경로에 마운트 시 subPath: gh 또는 subPath: mock-gh를
  # 사용하여 단일 파일만 마운트해야 합니다.
  run_patch

  local sub_path
  sub_path=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output")
      | .container.volumeMounts[]
      | select(.name | test("mock-gh"))
      | .subPath)')

  # subPath가 설정되어 있어야 합니다 (단일 파일 마운트).
  [ -n "$sub_path" ]
}

@test "patch: mock-gh 볼륨 마운트가 readOnly로 설정된다" {
  # gh 바이너리는 실행만 되면 되므로 readOnly: true가 권장됩니다.
  run_patch

  local read_only
  read_only=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output")
      | .container.volumeMounts[]
      | select(.name | test("mock-gh"))
      | .readOnly)')

  [ "$read_only" = "true" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. 패치된 YAML 구조 무결성 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: 패치 후 YAML이 유효한 Kubernetes 리소스 형식을 유지한다" {
  run_patch

  # apiVersion과 kind 필드가 유지되어야 합니다.
  local api_version
  api_version=$(yaml_get_patched '.apiVersion')
  [ "$api_version" = "argoproj.io/v1alpha1" ]

  local kind
  kind=$(yaml_get_patched '.kind')
  [ "$kind" = "WorkflowTemplate" ]
}

@test "patch: 패치 후 spec.templates 배열에 export-cycle-output 템플릿이 존재한다" {
  run_patch

  local template_count
  template_count=$(yaml_get_patched \
    '[.spec.templates[] | select(.name == "export-cycle-output")] | length')
  [ "$template_count" -eq 1 ]
}

@test "patch: export-handler 컨테이너의 기존 workdir 볼륨 마운트가 유지된다" {
  # mock-gh 주입 후에도 /work 볼륨 마운트가 존재해야 합니다.
  run_patch

  local workdir_mount
  workdir_mount=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "export-cycle-output")
      | .container.volumeMounts[]
      | select(.name == "workdir")
      | .mountPath)')

  [ "$workdir_mount" = "/work" ]
}

@test "patch: 패치 후 YAML을 yq로 파싱할 수 있다 (유효한 YAML)" {
  run_patch

  # yq가 오류 없이 파싱할 수 있어야 합니다.
  run yq eval '.' "$DST_TEMPLATE"
  [ "$status" -eq 0 ]
}

@test "patch: 패치가 두 번 실행되어도 idempotent하게 동작한다" {
  # 동일한 src로 두 번 패치해도 동일한 결과가 나와야 합니다.
  run_patch

  local first_mock_gh_count
  first_mock_gh_count=$(grep -c "mock-gh" "$DST_TEMPLATE" || true)

  # 두 번째 패치: src를 다시 원본으로 사용
  DST_TEMPLATE2="$BATS_TEST_TMPDIR/workflow-template-patched2.yaml"
  patch_workflow_template_for_mock \
    "$SRC_TEMPLATE" \
    "$DST_TEMPLATE2" \
    "test-scenario"

  local second_mock_gh_count
  second_mock_gh_count=$(grep -c "mock-gh" "$DST_TEMPLATE2" || true)

  # 두 번 패치 결과에서 mock-gh 출현 횟수가 동일해야 합니다.
  [ "$first_mock_gh_count" -eq "$second_mock_gh_count" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 5. 다른 컨테이너에 mock-gh가 주입되지 않는지 검증 (격리성)
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: agent-job 템플릿에는 mock-gh 볼륨 마운트가 추가되지 않는다" {
  # mock-gh는 export-handler에만 주입되어야 합니다.
  # agent-job은 gh CLI를 사용하지 않으므로 mock-gh 마운트가 불필요합니다.
  run_patch

  local agent_gh_mount_count
  agent_gh_mount_count=$(yaml_get_patched \
    '([.spec.templates[] | select(.name == "agent-job")
      | .container.volumeMounts[]
      | select(.name | test("mock-gh"))] | length)')

  [ "$agent_gh_mount_count" -eq 0 ]
}

@test "patch: mcp-daemon 템플릿에는 mock-gh 볼륨 마운트가 추가되지 않는다" {
  run_patch

  local mcp_gh_mount_count
  mcp_gh_mount_count=$(yaml_get_patched \
    '([.spec.templates[] | select(.name == "mcp-daemon")
      | .container.volumeMounts[]
      | select(.name | test("mock-gh"))] | length)')

  [ "$mcp_gh_mount_count" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. mock-scenario-data (SCENARIO_DIR) 주입 검증
# ═══════════════════════════════════════════════════════════════════════════════

@test "patch: agent-job 템플릿에 mock-scenario-data 볼륨이 추가된다" {
  run_patch

  local scenario_volume_count
  scenario_volume_count=$(yaml_get_patched \
    '([.spec.templates[] | select(.name == "agent-job")
      | .volumes[]
      | select(.name == "mock-scenario-data")] | length)')

  [ "$scenario_volume_count" -eq 1 ]
}

@test "patch: agent-job 컨테이너에 mock-scenario-data 볼륨 마운트가 /scenario에 마운트된다" {
  run_patch

  local mount_path
  mount_path=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "agent-job")
      | .container.volumeMounts[]
      | select(.name == "mock-scenario-data")
      | .mountPath)')

  [ "$mount_path" = "/scenario" ]
}

@test "patch: agent-job 컨테이너에 SCENARIO_DIR 환경변수가 /scenario로 설정된다" {
  run_patch

  local scenario_dir
  scenario_dir=$(yaml_get_patched \
    '(.spec.templates[] | select(.name == "agent-job")
      | .container.env[]
      | select(.name == "SCENARIO_DIR")
      | .value)')

  [ "$scenario_dir" = "/scenario" ]
}
