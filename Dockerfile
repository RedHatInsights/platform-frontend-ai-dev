FROM registry.access.redhat.com/ubi9/ubi:latest

# System deps + Python 3.12 + Chromium runtime libraries
RUN dnf install -y --nodocs --allowerasing \
    python3.12 python3.12-pip python3.12-devel \
    git \
    openssh-clients \
    curl \
    jq \
    bubblewrap \
    socat \
    alsa-lib \
    atk \
    at-spi2-atk \
    at-spi2-core \
    cairo \
    cups-libs \
    dbus-libs \
    libdrm \
    mesa-libgbm \
    glib2 \
    nspr \
    nss \
    pango \
    libX11 \
    libxcb \
    libXcomposite \
    libXdamage \
    libXext \
    libXfixes \
    libxkbcommon \
    libXrandr \
    && dnf clean all

# Node.js 22 (official binary tarball)
RUN ARCH=$(uname -m | sed 's/x86_64/x64/' | sed 's/aarch64/arm64/') \
    && curl -fsSL "https://nodejs.org/dist/v22.15.0/node-v22.15.0-linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local --strip-components=1


# Headless Chromium via Playwright (avoids EPEL/CentOS RPMs)
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN npx playwright install chromium

# Make python3.12 the default
RUN ln -sf /usr/bin/python3.12 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python

# gh CLI
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/') \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local --strip-components=1

# glab CLI
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/') \
    && curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v1.51.0/downloads/glab_1.51.0_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=2 bin/glab

# uv
RUN pip3.12 install uv

# Non-root user (Claude Code rejects root)
RUN useradd -m -s /bin/bash botuser
WORKDIR /home/botuser/app

# Copy project files and install Python deps (as root so uv is available)
COPY pyproject.toml uv.lock* ./
COPY bot/ bot/
RUN uv sync --frozen --no-dev
ENV PATH="/home/botuser/app/.venv/bin:$PATH"
ENV CLAUDE_CODE_USE_VERTEX=1
ENV VERTEX_LOCATION=global

# Copy bot config files
COPY config.json project-repos.json CLAUDE.md .mcp.json entrypoint.sh ./
COPY .claude/ .claude/
COPY personas/ personas/

# Fix ownership
RUN chown -R botuser:botuser /home/botuser/app

USER botuser

# SSH config — tunnel through Squid proxy for network isolation
RUN mkdir -p /home/botuser/.ssh && chmod 700 /home/botuser/.ssh
RUN echo -e "Host github.com-bot\n  HostName github.com\n  User git\n  IdentityFile /home/botuser/.ssh/id_ed25519\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new\n  ProxyCommand socat - PROXY:proxy:%h:%p,proxyport=3128\n\nHost gitlab.cee.redhat.com\n  IdentityFile /home/botuser/.ssh/id_ed25519\n  StrictHostKeyChecking accept-new\n  ProxyCommand socat - PROXY:proxy:%h:%p,proxyport=3128" \
    > /home/botuser/.ssh/config && chmod 600 /home/botuser/.ssh/config
ENV GIT_SSH_COMMAND="ssh -F /home/botuser/.ssh/config"

# Pre-add known host keys so first connection doesn't warn
RUN ssh-keyscan -t ed25519,rsa,ecdsa github.com >> /home/botuser/.ssh/known_hosts 2>/dev/null \
    && ssh-keyscan -t ed25519,rsa,ecdsa gitlab.cee.redhat.com >> /home/botuser/.ssh/known_hosts 2>/dev/null; \
    chmod 600 /home/botuser/.ssh/known_hosts

# Git config
RUN git config --global user.name "platex-rehor-bot" \
    && git config --global user.email "platform-experience-services@redhat.com" \
    && git config --global gpg.format openpgp \
    && git config --global commit.gpgsign true

ENTRYPOINT ["bash", "entrypoint.sh"]
