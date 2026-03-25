// Agent execution environments (keep in sync with router/src/router/environments.py)

export interface AgentEnvironment {
  id: string;
  image: string;
  description: string;
  capabilities: string[];
  is_default: boolean;
}

export const AVAILABLE_ENVIRONMENTS: AgentEnvironment[] = [
  {
    id: "default",
    image: "ghcr.io/dlddu/pure-agent/claude-agent:latest",
    description:
      "기본 환경. Claude Code CLI, git, curl, jq 포함. 일반적인 코딩 작업에 적합.",
    capabilities: ["claude-code", "git", "shell"],
    is_default: true,
  },
  {
    id: "python-analysis",
    image: "ghcr.io/dlddu/pure-agent/python-agent:latest",
    description:
      "Python 분석 환경. pandas, numpy, matplotlib 등 데이터 분석 도구 포함.",
    capabilities: ["python", "pip", "data-analysis", "git", "shell"],
    is_default: false,
  },
  {
    id: "infra",
    image: "ghcr.io/dlddu/pure-agent/infra-agent:latest",
    description:
      "인프라 환경. kubectl, helm, AWS CLI 등 인프라 관리 도구 포함.",
    capabilities: ["kubectl", "helm", "aws-cli", "git", "shell"],
    is_default: false,
  },
];

export const ENVIRONMENT_IDS = AVAILABLE_ENVIRONMENTS.map((e) => e.id);
export const DEFAULT_ENVIRONMENT = AVAILABLE_ENVIRONMENTS.find((e) => e.is_default)!;
