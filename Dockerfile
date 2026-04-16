FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bash \
    git \
    python3 \
    python3-pip \
    xz-utils \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create sandbox user (uid/gid 1000) — required by OpenShell
RUN groupadd -g 1000 sandbox && \
    useradd -u 1000 -g sandbox -m -s /bin/bash sandbox

# Install Hermes Agent as root, then make accessible to sandbox user.
# The install script puts the binary in /root/.local/bin/ and config in /root/.hermes/.
# We move these to the sandbox user's home so OpenShell's run_as_user can access them.
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash || true \
    && HERMES_BIN=$(command -v hermes || echo "/root/.local/bin/hermes") \
    && test -f "$HERMES_BIN" || (echo "Hermes binary not found after install" && exit 1) \
    && cp "$HERMES_BIN" /usr/local/bin/hermes \
    && chmod 755 /usr/local/bin/hermes

# Copy hermes config from root's install to sandbox user's home
RUN if [ -d /root/.hermes ]; then \
      cp -a /root/.hermes /home/sandbox/.hermes; \
      chown -R sandbox:sandbox /home/sandbox/.hermes; \
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
