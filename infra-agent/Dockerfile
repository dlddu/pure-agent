# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/dlddu/pure-agent"
LABEL org.opencontainers.image.description="Infrastructure agent container for pure-agent"

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
    unzip \
    groff \
    less \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS CLI v2
RUN ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then \
         CLI_ARCH="aarch64"; \
       else \
         CLI_ARCH="x86_64"; \
       fi \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${CLI_ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscli.zip /tmp/aws

RUN useradd -m -s /bin/bash --no-log-init claude

USER claude
WORKDIR /home/claude

# Install Claude Code
ARG CLAUDE_CODE_CHANNEL=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_CHANNEL"

ENV PATH="/home/claude/.local/bin:$PATH"

# Settings, shared defaults, and hooks (from claude-agent, rarely change)
COPY --chown=claude:claude claude-agent/settings.json /home/claude/.claude/settings.json
COPY --chown=claude:claude claude-agent/shared/ /home/claude/shared/
COPY --chown=claude:claude --chmod=755 claude-agent/hooks/ /home/claude/hooks/

# Library modules and entrypoint (from claude-agent, change occasionally)
COPY --chown=claude:claude --chmod=755 claude-agent/lib/ /home/claude/lib/
COPY --chown=claude:claude --chmod=755 claude-agent/entrypoint.sh /home/claude/entrypoint.sh
COPY --chown=claude:claude claude-agent/extract-result.jq /home/claude/extract-result.jq

# Project guidelines (environment-specific)
COPY --chown=claude:claude infra-agent/CLAUDE.md /home/claude/CLAUDE.md

ENTRYPOINT ["/home/claude/entrypoint.sh"]
