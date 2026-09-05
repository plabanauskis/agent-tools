<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="pibox" width="320">
</picture>

<p><strong>Give Pi full control of your project — pibox is designed to narrow the blast radius.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · amd64" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20amd64-555">
  <img alt="Built for Pi" src="https://img.shields.io/badge/built%20for-Pi-4B607C">
</p>

</div>

`pibox` launches the exact host Pi installation as the host user inside a sysbox-backed Docker container. Pi [runs tools with all permissions by default](https://pi.dev); no approval-bypass or sandbox-bypass option exists or is added. The whole Pi process, including built-in tools, user `!` commands, and extension tools, executes inside the external container boundary.

The mounted project is real and writable. Run pibox from a Git repository whenever possible: Git history is the practical undo path. Outside a repository, pibox warns that edits and deletions have no Git undo and requires confirmation.

> Linux host and amd64 are required. The design is adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT) and follows Pi's documented whole-process [plain Docker pattern](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/containerization.md), with sysbox and a richer development image added.

## Security model

The intended blast radius is narrow but real: Pi can fully change the mounted project, mounted Pi agent state, dependency caches, and per-project inner-Docker data.

- Docker runs with `--runtime=sysbox-runc`. Sysbox user-namespace isolation is the intended security boundary.
- The selected project and `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}` are mounted read-write at path-identical locations. A custom `PI_CODING_AGENT_SESSION_DIR` outside agent state receives its own path-identical mount.
- The resolved host Pi installation is mounted read-only. Supported layouts are the current `@earendil-works/pi-coding-agent` npm package and an official compiled Pi directory with adjacent runtime assets.
- The host Docker socket is never mounted, and pibox does not use privileged mode or host networking. Docker available inside the box is an isolated inner daemon with project-specific storage.
- Host SSH and GitHub CLI credentials are not mounted. A read-only `.gitconfig` provides commit identity but no push credential.
- Provider credentials in Pi's mounted `auth.json` can be refreshed in place. pibox also forwards only an explicit allowlist of supported provider environment variables; it never forwards the entire host environment.
- There is no network-egress firewall or kernel-escape protection. Treat the project and Pi state as intentionally writable, review the boundary, and use pibox only where that tradeoff is acceptable.

Mounting host agent state exposes authentication, settings, packages, sessions, and any installed extension code to the container. Extensions run with the same in-box authority as Pi. If you want isolated state instead, set `PI_CODING_AGENT_DIR` to a dedicated host directory before running both `pibox doctor` and `pibox`.

## Prerequisites

1. **Docker:** `docker --version` works without sudo, and `docker info -f '{{.Runtimes}}'` lists `sysbox-runc`.
2. **sysbox:** install and configure sysbox-ce for Docker. No fallback runtime is accepted.
3. **Host Pi:** `pi` is on `PATH` and comes from `@earendil-works/pi-coding-agent` or an official compiled directory. pibox mounts this installation instead of baking in a second version.
4. **Pi state:** run Pi on the host so `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}` exists. Create a configured custom `PI_CODING_AGENT_SESSION_DIR` before launch.
5. **Authentication:** use `/login` in host Pi so `auth.json` contains provider state, or export a supported provider credential. `pibox doctor` reports an empty auth configuration, but launch does not gate on one auth method because Pi also supports local/custom providers.

## Build and install

```bash
pitools enable pibox
pibox doctor
pibox build
```

The image defaults to `pibox:latest` and is built locally for the current username, UID, GID, and home path. Set `PIBOX_IMAGE` to another image name or `PIBOX_SHARE_DIR` to a directory containing the pibox `Dockerfile`.

The image includes Node 24, Python 3 + `uv`, Go 1.26.x, Rust stable, .NET 10, GitHub CLI, Git, jq, ripgrep, fd, OpenSSL, socat, and inner Docker + Compose. Pi itself is deliberately not baked in.

## Usage

```bash
cd ~/code/my-project
pibox                                  # Pi in the sysbox container
pibox --model anthropic/claude-sonnet  # pass Pi arguments unchanged
pibox --no-extensions                  # any Pi CLI option works
pibox doctor
pibox version
```

The first word `build`, `doctor`, `uninstall`, `help`, or `version` is a pibox subcommand. Any other arguments pass to Pi unchanged. `PI_SKIP_VERSION_CHECK=1` is set in-box because the host-mounted Pi installation is the version source.

### Provider environment

Mounted `auth.json` is preferred. When environment credentials are used, pibox forwards an explicit list covering Pi's built-in Anthropic, OpenAI/Azure, Google, Bedrock, OpenRouter, Cloudflare, Mistral, Groq, Cerebras, xAI, DeepSeek, NVIDIA, ZAI, Qwen, MiniMax, Xiaomi, Kimi, and other supported providers, plus proxy variables. Unrelated environment variables and credential directories such as `~/.aws` are not forwarded.

### Ports, caches, and inner Docker

The default host-to-box port range is `3000-3010`. Add ports with `PIBOX_PORTS` (space-separated), or create `<repo>/.pibox/ports` with one port or range per line:

```bash
PIBOX_PORTS="8080 5173" pibox
```

Services must listen on `0.0.0.0` in the box. The box starts its inner Docker daemon unless `PIBOX_NO_DOCKER=1` is set. Shared dependency caches are `pibox-npm`, `pibox-cargo`, `pibox-go`, `pibox-uv`, and `pibox-nuget`; inner Docker data uses `pibox-docker-<project>`.

For a visual reminder, pibox tints the terminal background. Configure `PIBOX_TINT` or disable it with `PIBOX_NO_TINT=1`. The container receives `PIBOX=1` and `PIBOX_VERSION`.

## Uninstall

```bash
pibox uninstall        # image and shared caches; asks before project data volumes
pitools disable pibox  # remove the command link
```

Run `pibox uninstall` before `pitools uninstall`. Project-specific data volumes are deleted only after explicit confirmation.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sysbox runtime not found` | Install/configure sysbox-ce and verify Docker lists `sysbox-runc`. |
| Host Pi layout is unsupported | Install the current `@earendil-works/pi-coding-agent` package or use an official compiled Pi directory. |
| Agent state is missing | Run `pi` on the host first, or set `PI_CODING_AGENT_DIR` to an existing directory. |
| Custom session directory is missing | Create `PI_CODING_AGENT_SESSION_DIR` before launching. |
| `doctor` reports auth missing | Use `/login` in host Pi or export a supported provider credential. |
| Image is missing | Run `pibox build`, or accept the interactive build prompt. |
| Inner Docker is initially unavailable | Wait until `docker info` succeeds, or use `PIBOX_NO_DOCKER=1`. |
| Browser cannot reach a service | Bind it to `0.0.0.0` and publish the port with `PIBOX_PORTS` or `.pibox/ports`. |
| Non-Git warning appears | Continue only after accepting the lack of Git undo, or use a repository. |
