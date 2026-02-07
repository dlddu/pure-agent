FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash claude

USER claude
WORKDIR /home/claude

# Install Claude Code (stable)
RUN curl -fsSL https://claude.ai/install.sh | bash -s stable

ENV PATH="/home/claude/.local/bin:$PATH"

WORKDIR /workspace

COPY CLAUDE.md /workspace/CLAUDE.md

# Stop Hook: ensure export_config.json is written before session ends
COPY --chown=claude:claude hooks/ /home/claude/hooks/
RUN chmod +x /home/claude/hooks/*.sh

# Claude Code settings (hook registration)
COPY --chown=claude:claude settings.json /home/claude/.claude/settings.json

ENTRYPOINT ["claude"]
