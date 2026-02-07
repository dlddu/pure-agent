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
│  │  │  :8080        │         │    :8443             │     │  │
│  │  │               │         │    (LiteLLM Proxy)   │     │  │
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
  - `ANTHROPIC_BASE_URL`을 내부 서비스 URL(`http://mcp-stack-{workflow}:8443`)로 설정
- **도구 접근**: Agent → MCP Server를 통해서만 외부 서비스 연동
- **내부 통신**: Kubernetes Service 기반 Pod 간 통신

> **현재 한계**: `ANTHROPIC_BASE_URL` 설정을 통한 소프트 격리만 구현되어 있다.
> Agent 컨테이너의 외부 네트워크 접근을 차단하는 Kubernetes NetworkPolicy는 미구현 상태.

### 2. 에이전트 오케스트레이션

Argo Workflows 기반으로 Agent → Router 반복 루프를 실행한다.

- **Agent → Router 루프**: Agent가 작업을 수행하고, Router가 계속 여부를 판단
- **재귀적 depth 제어**: 기본 `max_depth=10`, 무한 루프 방지
- **사이클별 출력 내보내기**: 각 사이클의 결과를 JSON으로 저장
- **자동 리소스 정리**: 워크플로우 완료 후 Pod, Service, PVC 자동 삭제

### 3. LLM Gateway

LiteLLM Proxy 기반 API 프록시. Agent의 LLM 호출을 중계한다.

### 4. MCP Server

Model Context Protocol HTTP 서버. Agent가 사용할 도구를 제공한다.

- **도구 시스템**
  - `get_export_actions`: 사용 가능한 export action 목록 조회
  - `set_export_config`: 작업 완료 후 export 설정 저장 (action 타입, 요약, PR 설정 등)
  - `request_feature`: MCP 서버 기능이 부족하여 작업을 수행하지 못했을 때 개발자에게 기능 확장을 요청
- **Health/Readiness 프로브**: Kubernetes 헬스체크 지원

### 5. Export 시스템

Agent 작업 결과를 외부로 내보내는 파이프라인. Agent가 `set_export_config`를 호출하면 Router가 종료를 판단하고, Export Handler가 설정에 따라 후처리를 실행한다.

- **Stop Hook 강제**: Agent는 `set_export_config` 호출 없이 종료할 수 없다. 호출하지 않으면 Stop Hook이 차단하고 에이전트에게 호출을 요구한다.
- **Export Action 타입**:
  - `none`: 추가 산출물 없음. 작업 요약 코멘트만 Linear 이슈에 추가
  - `upload_workspace`: workspace 전체를 압축하여 Linear 이슈에 첨부
  - `report`: 마크다운 분석 리포트를 Linear 이슈 코멘트로 추가
  - `create_pr`: GitHub Pull Request 생성
- **실행 흐름**: Agent → `set_export_config` 호출 → Router 종료 판단 → Export Handler 실행 → Linear 코멘트 + 선택된 action 수행

## 프로젝트 구조

```
pure-agent/
├── claude-agent/
│   ├── Dockerfile                    # Claude Code CLI 컨테이너
│   ├── CLAUDE.md                     # Agent 프로젝트 가이드라인
│   ├── settings.json                 # Claude Code 훅 설정
│   └── hooks/
│       └── ensure-export-config.sh   # Stop Hook (export_config 강제)
├── mcp-server/
│   ├── Dockerfile                    # MCP Server 컨테이너
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example                  # 환경변수 예시
│   └── src/
│       ├── index.ts                  # 엔트리포인트
│       ├── server.ts                 # MCP 서버 설정
│       ├── transport.ts              # HTTP 전송 계층
│       ├── tools/
│       │   ├── export-actions.ts     # export 관련 도구
│       │   └── request-feature.ts    # request_feature 도구
│       └── services/
│           └── linear.ts             # Linear API 클라이언트
├── export-handler/
│   ├── Dockerfile                    # Export Handler 컨테이너
│   ├── package.json
│   └── src/
│       ├── index.ts                  # 핸들러 오케스트레이터
│       ├── schema.ts                 # Export 설정 검증 스키마
│       └── actions/
│           ├── post-summary.ts       # Linear 요약 코멘트
│           ├── post-report.ts        # Linear 리포트 코멘트
│           ├── upload-workspace.ts   # workspace 압축 업로드
│           └── create-pr.ts          # GitHub PR 생성
├── router/
│   ├── Dockerfile                    # Router 컨테이너
│   └── router.py                     # 계속/종료 판단 로직
├── k8s/
│   ├── workflow-template.yaml        # Argo WorkflowTemplate (오케스트레이션)
│   ├── llm-gateway-configmap.yaml    # LiteLLM 설정 ConfigMap
│   └── secret.yaml.example           # Secret 예시 파일
├── .github/workflows/
│   ├── build-claude-agent.yaml       # Claude Agent 이미지 빌드 CI
│   ├── build-mcp-server.yaml         # MCP Server 이미지 빌드 CI
│   ├── build-export-handler.yaml     # Export Handler 이미지 빌드 CI
│   └── build-router.yaml             # Router 이미지 빌드 CI
└── .devcontainer/
    └── devcontainer.json             # Dev Container 설정
```

## 기술 스택

| 영역 | 기술 |
|------|------|
| 오케스트레이션 | Argo Workflows, Kubernetes |
| LLM Gateway | LiteLLM Proxy |
| MCP Server | Node.js 22, TypeScript, Express |
| Export Handler | Node.js 22, TypeScript, Linear SDK, GitHub CLI |
| Router | Python 3.12 |
| AI | Claude Code CLI, Anthropic API |
| 외부 연동 | Linear SDK, GitHub (PR 생성) |
| 시크릿 관리 | Kubernetes Secret (컨테이너별 분리) |
| 스토리지 | AWS EFS |
| CI/CD | GitHub Actions, GitHub Container Registry |

## 시작하기

### 사전 요구 사항

- Kubernetes 클러스터 (Argo Workflows 설치)
- EFS StorageClass (`efs-sc`)
- Kubernetes Secret 생성 (`k8s/secret.yaml.example` 참고):

| Secret 이름 | 키 | 사용 컨테이너 |
|---|---|---|
| `mcp-server-secrets` | `LINEAR_API_KEY`, `LINEAR_TEAM_ID` | MCP Server |
| `llm-gateway-secrets` | `ANTHROPIC_API_KEY`, `LITELLM_MASTER_KEY` | LLM Gateway |
| `agent-secrets` | `LITELLM_MASTER_KEY` | Claude Agent |
| `export-handler-secrets` | `LINEAR_API_KEY`, `LINEAR_TEAM_ID`, `GITHUB_TOKEN` | Export Handler |

