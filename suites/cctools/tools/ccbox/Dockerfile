# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

# Mirror the host account so paths inside the box are identical to the host: same UID/GID,
# username, and $HOME. ccbox passes these at build time (see 'ccbox build').
ARG UID=1000
ARG GID=1000
ARG USERNAME=dev
ARG USER_HOME=/home/dev
ARG NODE_MAJOR=24

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/go/bin:${USER_HOME}/.cargo/bin:${USER_HOME}/.dotnet:${PATH}"
ENV DOTNET_ROOT=${USER_HOME}/.dotnet

# core packages
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg jq ripgrep fd-find less unzip zip \
      build-essential pkg-config python3 python3-pip python3-venv \
      libssl-dev openssl socat sudo openssh-client libicu72 \
 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Node.js — for language toolchain + npx-based plugins (context7, *-lsp). Claude Code itself
# is NOT installed here: ccbox mounts the host's own claude binary read-only, so the box
# always runs the exact host version (no in-image install, no version skew, no rebuild to update).
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

ARG GO_VERSION=1.26.4

# uv (system-wide)
RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Go
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz

# non-root user mirroring the host account (Claude refuses --dangerously-skip-permissions as root)
RUN groupadd -g ${GID} "${USERNAME}" 2>/dev/null || true \
 && useradd -m -u ${UID} -g ${GID} -d "${USER_HOME}" -s /bin/bash "${USERNAME}" \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"

# Inner Docker engine + Compose v2, so the agent can run the project's own stack
RUN install -m0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/* \
 && usermod -aG docker "${USERNAME}"

USER ${USERNAME}
WORKDIR ${USER_HOME}

ARG DOTNET_CHANNEL=10.0

# Rust (PATH already includes ~/.cargo/bin)
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable

# .NET SDK (PATH already includes ~/.dotnet)
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir "${USER_HOME}/.dotnet" \
 && rm /tmp/dotnet-install.sh

# The Go/Rust/.NET dirs are non-standard, so a login shell's /etc/profile would otherwise
# clobber the image ENV PATH and hide them. Re-add via /etc/profile.d so the toolchains are
# on PATH no matter how the agent's shell is spawned (login or non-login).
RUN printf '%s\n' \
      "export PATH=\"/usr/local/go/bin:${USER_HOME}/.cargo/bin:${USER_HOME}/.dotnet:\$PATH\"" \
      "export DOTNET_ROOT=${USER_HOME}/.dotnet" \
    | sudo tee /etc/profile.d/ccbox-toolchains.sh >/dev/null

# entrypoint.sh last, after the heavy toolchain layers, so editing it doesn't bust their cache.
# COPY runs as root regardless of the USER above, so it can write to /usr/local/bin.
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# ccbox always supplies the command (the host claude binary path). Bare runs get a shell.
CMD ["bash"]
