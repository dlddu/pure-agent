# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm

LABEL org.opencontainers.image.source="https://github.com/dlddu/pure-agent"
LABEL org.opencontainers.image.description="Planner agent container for pure-agent (Claude Code CLI-based)"

ARG BUILD_DATE
ARG GIT_SHA
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install planner Python package as root (before USER switch)
COPY planner/pyproject.toml /app/pyproject.toml
COPY planner/src/ /app/src/
RUN pip install --no-cache-dir /app && rm -rf /app

RUN useradd -m -s /bin/bash --no-log-init claude

USER claude
WORKDIR /home/claude

# Install Claude Code CLI
ARG CLAUDE_CODE_CHANNEL=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_CHANNEL"

ENV PATH="/home/claude/.local/bin:$PATH"

# Claude Code settings (haiku model, no hooks)
COPY --chown=claude:claude planner/settings.json /home/claude/.claude/settings.json

# Planner guidelines
COPY --chown=claude:claude planner/CLAUDE.md /home/claude/CLAUDE.md
ENV PLANNER_CLAUDE_MD=/home/claude/CLAUDE.md

CMD ["planner"]
