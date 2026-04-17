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

# Copy source + config to sandbox user's home
RUN if [ -d /root/.hermes ]; then \
      cp -a /root/.hermes /home/sandbox/.hermes; \
      chown -R sandbox:sandbox /home/sandbox/.hermes; \
    fi

# Fix hardcoded /root/.hermes paths in the editable-install finder.
# The venv has __editable__*_finder.py files that reference /root/.hermes/... —
# rewrite them to /home/sandbox/.hermes/...
RUN find /home/sandbox/.hermes/hermes-agent/venv -name "__editable__*finder.py" \
      -exec sed -i 's|/root/.hermes|/home/sandbox/.hermes|g' {} + 2>/dev/null || true \
    && find /home/sandbox/.hermes/hermes-agent/venv -name "*.pth" \
      -exec sed -i 's|/root/.hermes|/home/sandbox/.hermes|g' {} + 2>/dev/null || true \
    && find /home/sandbox/.hermes/hermes-agent/venv -name "RECORD" \
      -exec sed -i 's|/root/.hermes|/home/sandbox/.hermes|g' {} + 2>/dev/null || true

# Delete compiled .pyc cache so Python recompiles from the patched .py files
RUN find /home/sandbox/.hermes/hermes-agent/venv -name "__editable__*finder*.pyc" -delete 2>/dev/null || true \
    && find /home/sandbox/.hermes/hermes-agent/venv -path "*__pycache__*" -name "*editable*finder*" -delete 2>/dev/null || true

# Also fix the hermes binary shebang if it references /root
RUN HERMES_BIN="/home/sandbox/.hermes/hermes-agent/venv/bin/hermes" \
    && if [ -f "$HERMES_BIN" ]; then \
         sed -i '1s|/root/.hermes|/home/sandbox/.hermes|g' "$HERMES_BIN"; \
       fi

# Create wrapper at /usr/local/bin/hermes (needs root to write there)
USER root
RUN HERMES_BIN="/home/sandbox/.hermes/hermes-agent/venv/bin/hermes" \
    && if [ -f "$HERMES_BIN" ]; then \
         printf '#!/bin/bash\nexec "%s" "$@"\n' "$HERMES_BIN" > /usr/local/bin/hermes; \
         chmod 755 /usr/local/bin/hermes; \
       else \
         echo "WARNING: $HERMES_BIN not found"; \
       fi

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
