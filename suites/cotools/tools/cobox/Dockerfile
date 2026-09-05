# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

# Mirror the host account so paths inside cobox stay identical to the host.
ARG UID=1000
ARG GID=1000
ARG USERNAME=dev
ARG USER_HOME=/home/dev
ARG NODE_MAJOR=24

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/go/bin:${USER_HOME}/.cargo/bin:${USER_HOME}/.dotnet:${PATH}"
ENV DOTNET_ROOT=${USER_HOME}/.dotnet

# Core packages
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

# Node.js is provided for project tooling. Codex is deliberately not installed:
# cobox mounts the exact host installation read-only at launch time.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

ARG GO_VERSION=1.26.4

# uv (system-wide)
RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Go
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz

# Non-root user mirroring the host account.
RUN groupadd -g ${GID} "${USERNAME}" 2>/dev/null || true \
 && useradd -m -u ${UID} -g ${GID} -d "${USER_HOME}" -s /bin/bash "${USERNAME}" \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"

# Inner Docker engine + Compose v2, so the agent can run the project's stack.
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

# Preserve non-standard toolchains for shells that reconstruct PATH from profile.
RUN printf '%s\n' \
      "export PATH=\"/usr/local/go/bin:${USER_HOME}/.cargo/bin:${USER_HOME}/.dotnet:\$PATH\"" \
      "export DOTNET_ROOT=${USER_HOME}/.dotnet" \
    | sudo tee /etc/profile.d/cobox-toolchains.sh >/dev/null

# Entrypoint comes last so edits do not invalidate expensive toolchain layers.
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
