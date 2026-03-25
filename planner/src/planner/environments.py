"""Agent execution environments: image registry and lookup."""

from __future__ import annotations

from dataclasses import dataclass

DEFAULT_ENVIRONMENT_ID = "default"


@dataclass(frozen=True, slots=True)
class Environment:
    """A predefined agent execution environment."""

    id: str
    image: str
    description: str
    capabilities: tuple[str, ...]


# 사전 정의된 환경 목록 (keep in sync with mcp-server environment-constants.ts)
ENVIRONMENTS: tuple[Environment, ...] = (
    Environment(
        id="default",
        image="ghcr.io/dlddu/pure-agent/claude-agent:latest",
        description="기본 환경. Claude Code CLI, git, curl, jq 포함. 일반적인 코딩 작업에 적합.",
        capabilities=("claude-code", "git", "shell"),
    ),
    Environment(
        id="python-analysis",
        image="ghcr.io/dlddu/pure-agent/python-agent:latest",
        description="Python 분석 환경. pandas, numpy, matplotlib 등 데이터 분석 도구 포함.",
        capabilities=("python", "pip", "data-analysis", "git", "shell"),
    ),
    Environment(
        id="infra",
        image="ghcr.io/dlddu/pure-agent/infra-agent:latest",
        description="인프라 환경. kubectl, helm, AWS CLI 등 인프라 관리 도구 포함.",
        capabilities=("kubectl", "helm", "aws-cli", "git", "shell"),
    ),
)

ENVIRONMENT_MAP: dict[str, Environment] = {env.id: env for env in ENVIRONMENTS}


def resolve_image(environment_id: str | None) -> str:
    """Resolve an environment ID to its container image. Falls back to default."""
    if not environment_id:
        return ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
    env = ENVIRONMENT_MAP.get(environment_id)
    if env is None:
        return ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
    return env.image
