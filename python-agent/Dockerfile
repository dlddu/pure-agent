# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/dlddu/pure-agent"
LABEL org.opencontainers.image.description="Python analysis agent container for pure-agent"

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
    python3 \
    python3-pip \
    python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash --no-log-init claude

USER claude
WORKDIR /home/claude

# Create a virtual environment for pip packages
RUN python3 -m venv /home/claude/.venv
ENV PATH="/home/claude/.venv/bin:/home/claude/.local/bin:$PATH"

# Install Python data analysis libraries
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    matplotlib \
    seaborn \
    scipy \
    scikit-learn \
    jupyter \
    openpyxl \
    pyarrow

# Install Claude Code
ARG CLAUDE_CODE_CHANNEL=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_CHANNEL"

# Settings, shared defaults, and hooks (from claude-agent, rarely change)
COPY --chown=claude:claude claude-agent/settings.json /home/claude/.claude/settings.json
COPY --chown=claude:claude claude-agent/shared/ /home/claude/shared/
COPY --chown=claude:claude --chmod=755 claude-agent/hooks/ /home/claude/hooks/

# Library modules and entrypoint (from claude-agent, change occasionally)
COPY --chown=claude:claude --chmod=755 claude-agent/lib/ /home/claude/lib/
COPY --chown=claude:claude --chmod=755 claude-agent/entrypoint.sh /home/claude/entrypoint.sh
COPY --chown=claude:claude claude-agent/extract-result.jq /home/claude/extract-result.jq

# Project guidelines (environment-specific)
COPY --chown=claude:claude python-agent/CLAUDE.md /home/claude/CLAUDE.md

ENTRYPOINT ["/home/claude/entrypoint.sh"]
