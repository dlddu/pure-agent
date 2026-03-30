# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/dlddu/pure-agent"
LABEL org.opencontainers.image.description="Planner agent container for pure-agent (Claude Code CLI-based)"

ARG BUILD_DATE
ARG GIT_SHA
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    ca-certificates \
    jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Install planner Python package
COPY --chown=claude:claude planner/pyproject.toml /app/pyproject.toml
COPY --chown=claude:claude planner/src/ /app/src/

RUN python3 -m pip install --no-cache-dir --break-system-packages /app

CMD ["planner"]
