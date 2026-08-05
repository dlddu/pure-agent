# pure-agent

네트워크 격리 환경에서 Claude AI 에이전트를 실행하는 Kubernetes 기반 프레임워크.

## 아키텍처

```
┌─ Argo Workflow ──────────────────────────────────────────────┐
│                                                              │
│  ┌─ MCP Stack Pod ────────────────────────────────────────┐  │
│  │                                                        │  │
│  │  ┌──────────────┐         ┌──────────────────────┐     │  │
│  │  │  MCP Server   │         │    LLM Gateway       │     │  │
│  │  │  :8080        │         │    :80               │     │  │
│  │  │               │         │    (nginx proxy)      │     │  │
│  │  └──────▲────────┘         └──────▲───────────────┘     │  │
│  │         │                         │                     │  │
│  └─────────┼─────────────────────────┼─────────────────────┘  │
│            │ MCP 도구 호출            │ LLM API 호출          │
│            │                         │                     │  │
│  ┌─────────┼─────────────────────────┴─────────────────────┐  │
│  │         │            Planner                            │  │
│  │         │    (LLM 기반 실행 환경 선택)                     │  │
│  └─────────┼───────────────┬───────────────────────────────┘  │
│            │               │ 선택된 이미지                     │
│            │               ▼                                  │
│  ┌─────────┴─────────────────────────────────────────────┐    │
│  │                   Claude Agent (원샷 실행)             │    │
│  └─────────────────────────┬─────────────────────────────┘    │
│                            │                                  │
│                            ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                      Gate                               │  │
│  │              (transcript 업로드)                          │  │
│  └──────────────────────┬──────────────────────────────────┘  │
│                         │                                     │
│                         ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  Export Handler                         │  │
│  │                   (GitHub / S3)                          │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

## 기능

### 1. 네트워크 격리

Agent가 외부 네트워크에 직접 접근하지 않도록 모든 통신을 내부 서비스를 통해 라우팅한다.

- **LLM 호출**: Agent → 클러스터 내부 LLM Gateway → Anthropic API
  - `ANTHROPIC_BASE_URL`을 내부 서비스 URL(`http://{llm-gateway-daemon-ip}`)로 설정
- **도구 접근**: Agent → MCP Server를 통해서만 외부 서비스 연동
- **내부 통신**: Kubernetes Service 기반 Pod 간 통신

- **네트워크 정책**: Kubernetes NetworkPolicy로 Agent Pod의 외부 네트워크 접근을 차단
  - Egress 허용 대상: MCP Server(:8080), LLM Gateway(:80), kube-dns(:53)
  - 그 외 모든 외부 트래픽 차단

### 2. 에이전트 오케스트레이션

Argo Workflows 기반으로 Planner → Agent → Gate → Export 파이프라인을 원샷으로 실행한다.

- **원샷 실행**: Agent는 태스크당 한 번만 실행되며, 반복 루프 없이 종료된다
- **결과 내보내기**: 실행 결과를 JSON으로 저장하고 Export Handler가 후처리
- **자동 리소스 정리**: 워크플로우 완료 후 Pod, Service, PVC 자동 삭제

### 3. LLM Gateway

nginx 리버스 프록시 기반 API 게이트웨이. Agent의 LLM 호출을 Anthropic API로 중계한다.

### 4. MCP Server

Model Context Protocol HTTP 서버. Agent가 사용할 도구를 제공한다.

- **도구 레지스트리**: 플러그인 방식의 도구 등록/조회 시스템 (`McpTool` 인터페이스 기반)
- **Health/Readiness 프로브**: Kubernetes 헬스체크 지원

### 5. Planner

LLM 기반 에이전트 실행 환경 선택기. 태스크 프롬프트를 분석하여 최적의 컨테이너 이미지를 선택한다.

- **LLM 기반 라우팅**: Claude Haiku 모델이 태스크를 분석하여 적합한 환경을 자동 선택
- **사전 정의 환경**:
  | 환경 ID | 이미지 | 용도 |
  |---------|--------|------|
  | `default` | `claude-agent` | 일반 코딩, 코드 리뷰, 문서 작업, git 작업 |
  | `python-analysis` | `python-agent` | 데이터 분석, 시각화, pandas/numpy, ML/AI |
  | `infra` | `infra-agent` | Kubernetes, 인프라 관리, kubectl, Helm, AWS |
- **Fallback**: LLM Gateway 연결 실패, 응답 파싱 실패, 알 수 없는 환경 ID 반환 시 모두 `default` 환경으로 자동 전환
- **CLI**: `planner --prompt "태스크 설명" --output /tmp/agent_image.txt`

### 6. Gate

Agent 실행 후 세션 transcript(`/work/.transcripts`)를 transcript viewer API로 업로드한다. `TRANSCRIPT_UPLOAD_API_URL` 미설정 시 업로드를 건너뛴다. 업로드 실패는 워크플로우를 실패시키지 않는다 (best-effort).

### 7. Export 시스템

Agent 작업 결과를 외부로 내보내는 파이프라인. Agent가 `set_export_config`를 호출하면 Export Handler가 설정에 따라 후처리를 실행한다.

- **Stop Hook 강제**: Agent는 `set_export_config` 호출 없이 종료할 수 없다. 호출하지 않으면 Stop Hook이 차단하고 에이전트에게 호출을 요구한다.
- **실행 흐름**: Agent → `set_export_config` 호출 → Export Handler 실행 → 선택된 action 수행

## 기술 스택

| 영역 | 기술 |
|------|------|
| 오케스트레이션 | Argo Workflows, Kubernetes |
| LLM Gateway | nginx (리버스 프록시) |
| MCP Server | Node.js 22 (>=20), TypeScript, Express, MCP SDK, Zod |
| Export Handler | Node.js 22 (>=20), TypeScript, Zod, GitHub CLI |
| Planner | Python 3.12, Anthropic API (Claude Haiku) |
| Gate | Python 3.12 |
| AI | Claude Code CLI, Anthropic API |
| 테스트 | Vitest, pytest, Supertest |
| 외부 연동 | GitHub (PR 생성) |
| 시크릿 관리 | Kubernetes Secret (컨테이너별 분리) |
| 스토리지 | AWS EFS |
| CI/CD | GitHub Actions, GitHub Container Registry |

## 시작하기

### 사전 요구 사항

- Kubernetes 클러스터 (Argo Workflows 설치)
- EFS StorageClass (`efs`)
- Kubernetes Secret 생성 (`k8s/secrets.yaml.example` 참고):

| Secret 이름 | 키 | 사용 컨테이너 |
|---|---|---|
| `mcp-server-secrets` | `GATEKEEPER_URL`, `GATEKEEPER_API_KEY`, `GATEKEEPER_USER_ID` | MCP Server |
| `agent-secrets` | `CLAUDE_CODE_OAUTH_TOKEN` | Claude Agent |
| `export-handler-secrets` | `GITHUB_TOKEN` | Export Handler |
