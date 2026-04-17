FROM debian:bookworm-slim

# Install system dependencies.
# iproute2 is required by OpenShell's BYOC sandbox for network-namespace setup —
# without it the supervisor can't wire netns and kills the container at start.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bash \
    git \
    python3 \
    python3-pip \
    xz-utils \
    sudo \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Create sandbox user (uid/gid 1000) — required by OpenShell
RUN groupadd -g 1000 sandbox && \
    useradd -u 1000 -g sandbox -m -s /bin/bash sandbox

# Install Hermes Agent source as root (puts source in /root/.hermes/hermes-agent/).
# We only need the source — we'll create a fresh venv as the sandbox user below.
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash || true

# Copy source + config to sandbox user's home, re-install as non-editable
RUN if [ -d /root/.hermes ]; then \
      cp -a /root/.hermes /home/sandbox/.hermes; \
      chown -R sandbox:sandbox /home/sandbox/.hermes; \
    fi

USER sandbox

# Remove the root-built venv and create a fresh one with a non-editable install.
# The root venv has editable-install finders that hardcode /root/.hermes/ paths.
RUN rm -rf /home/sandbox/.hermes/hermes-agent/venv \
    && python3 -m venv /home/sandbox/.hermes/hermes-agent/venv \
    && /home/sandbox/.hermes/hermes-agent/venv/bin/pip install --no-cache-dir \
         /home/sandbox/.hermes/hermes-agent \
    && printf '#!/bin/bash\nexec /home/sandbox/.hermes/hermes-agent/venv/bin/python3 -m hermes_cli.main "$@"\n' \
         > /home/sandbox/.local/bin/hermes 2>/dev/null || true

# Also create wrapper at /usr/local/bin via a temp — USER sandbox can't write there,
# so we do it in a root layer below.

USER root
RUN printf '#!/bin/bash\nexec /home/sandbox/.hermes/hermes-agent/venv/bin/hermes "$@"\n' \
         > /usr/local/bin/hermes \
    && chmod 755 /usr/local/bin/hermes

USER sandbox

# Environment
WORKDIR /home/sandbox

ENV PATH="/usr/local/bin:$PATH"
ENV HOME="/home/sandbox"
ENV HERMES_HOME="/home/sandbox/.hermes"

# Persistent volumes (mounted at runtime):
#   /home/sandbox/.hermes  — Hermes memories, skills, config
#   /sandbox               — Agent working directory
VOLUME ["/home/sandbox/.hermes", "/sandbox"]

# Default: start the Hermes gateway
CMD ["hermes", "gateway"]
