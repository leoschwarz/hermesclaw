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

# Install Hermes Agent as root (installs to /root/.hermes/hermes-agent/venv).
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash || true

# Copy entire hermes install (venv + config) to sandbox user's home
RUN if [ -d /root/.hermes ]; then \
      cp -a /root/.hermes /home/sandbox/.hermes; \
      chown -R sandbox:sandbox /home/sandbox/.hermes; \
    fi

# Create a wrapper script at /usr/local/bin/hermes that uses the sandbox venv.
# The original binary has a hardcoded shebang to /root/.hermes/... which won't work.
RUN HERMES_VENV_PYTHON="/home/sandbox/.hermes/hermes-agent/venv/bin/python3" \
    && HERMES_SCRIPT="/home/sandbox/.hermes/hermes-agent/venv/bin/hermes" \
    && if [ -f "$HERMES_SCRIPT" ]; then \
         printf '#!/bin/bash\nexec "%s" "%s" "$@"\n' "$HERMES_VENV_PYTHON" "$HERMES_SCRIPT" > /usr/local/bin/hermes; \
         chmod 755 /usr/local/bin/hermes; \
       else \
         echo "WARNING: hermes script not found at $HERMES_SCRIPT"; \
       fi

# Set up sandbox user environment
USER sandbox
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
