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
│  ┌─────────┴─────────────────────────┴─────────────────────┐  │
│  │                   Claude Agent                          │  │
│  └─────────────────────────┬───────────────────────────────┘  │
│                            │                                  │
│                            ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                      Router                             │  │
│  │              (계속 / 종료 판단)                            │  │
│  └──────────────────────┬──────────────────────────────────┘  │
│                         │                                     │
│                         ▼ depth < max_depth 이면 Agent로 복귀  │
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

Argo Workflows 기반으로 Agent → Router 반복 루프를 실행한다.

- **Agent → Router 루프**: Agent가 작업을 수행하고, Router가 계속 여부를 판단
- **재귀적 depth 제어**: 기본 `max_depth=10`, 무한 루프 방지
- **사이클별 출력 내보내기**: 각 사이클의 결과를 JSON으로 저장
- **자동 리소스 정리**: 워크플로우 완료 후 Pod, Service, PVC 자동 삭제

### 3. LLM Gateway

nginx 리버스 프록시 기반 API 게이트웨이. Agent의 LLM 호출을 Anthropic API로 중계한다.

### 4. MCP Server

Model Context Protocol HTTP 서버. Agent가 사용할 도구를 제공한다.

- **도구 레지스트리**: 플러그인 방식의 도구 등록/조회 시스템 (`McpTool` 인터페이스 기반)
- **Health/Readiness 프로브**: Kubernetes 헬스체크 지원

### 5. Export 시스템

Agent 작업 결과를 외부로 내보내는 파이프라인. Agent가 `set_export_config`를 호출하면 Router가 종료를 판단하고, Export Handler가 설정에 따라 후처리를 실행한다.

- **Stop Hook 강제**: Agent는 `set_export_config` 호출 없이 종료할 수 없다. 호출하지 않으면 Stop Hook이 차단하고 에이전트에게 호출을 요구한다.
- **실행 흐름**: Agent → `set_export_config` 호출 → Router 종료 판단 → Export Handler 실행 → Linear 코멘트 + 선택된 action 수행

## 기술 스택

| 영역 | 기술 |
|------|------|
| 오케스트레이션 | Argo Workflows, Kubernetes |
| LLM Gateway | nginx (리버스 프록시) |
| MCP Server | Node.js 22 (>=20), TypeScript, Express, MCP SDK, Zod |
| Export Handler | Node.js 22 (>=20), TypeScript, Linear SDK, Zod, GitHub CLI |
| Router | Python 3.12 |
| AI | Claude Code CLI, Anthropic API |
| 테스트 | Vitest, pytest, Supertest |
| 외부 연동 | Linear SDK, GitHub (PR 생성) |
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
| `mcp-server-secrets` | `LINEAR_API_KEY`, `LINEAR_TEAM_ID` | MCP Server |
| `agent-secrets` | `CLAUDE_CODE_OAUTH_TOKEN` | Claude Agent |
| `export-handler-secrets` | `LINEAR_API_KEY`, `GITHUB_TOKEN`, `AWS_S3_BUCKET_NAME` | Export Handler |

