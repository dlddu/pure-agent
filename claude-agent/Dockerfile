# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/dlddu/pure-agent"
LABEL org.opencontainers.image.description="Claude Code agent container for pure-agent"

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

RUN useradd -m -s /bin/bash --no-log-init claude

USER claude
WORKDIR /home/claude

# Install Claude Code
ARG CLAUDE_CODE_CHANNEL=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_CHANNEL"

ENV PATH="/home/claude/.local/bin:$PATH"

# Settings, shared defaults, and hooks (rarely change)
COPY --chown=claude:claude settings.json /home/claude/.claude/settings.json
COPY --chown=claude:claude shared/ /home/claude/shared/
COPY --chown=claude:claude --chmod=755 hooks/ /home/claude/hooks/

# Library modules and entrypoint (change occasionally)
COPY --chown=claude:claude --chmod=755 lib/ /home/claude/lib/
COPY --chown=claude:claude --chmod=755 entrypoint.sh /home/claude/entrypoint.sh
COPY --chown=claude:claude extract-result.jq /home/claude/extract-result.jq

# Project guidelines (change most frequently)
COPY --chown=claude:claude CLAUDE.md /home/claude/CLAUDE.md

ENTRYPOINT ["/home/claude/entrypoint.sh"]
