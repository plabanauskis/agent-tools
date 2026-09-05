<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="cobox" width="320">
</picture>

<p><strong>Give Codex autonomous control of your project — cobox is designed to narrow the blast radius.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · amd64" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20amd64-555">
  <img alt="Built for Codex" src="https://img.shields.io/badge/built%20for-Codex-10A37F">
</p>

</div>

`cobox` launches the exact host Codex installation in a sysbox-backed Docker container and passes `--dangerously-bypass-approvals-and-sandbox` to it. The result is autonomous work on a real mounted project, with Docker + sysbox narrowing the blast radius rather than providing an absolute safety guarantee.

Run it from a Git repository whenever possible: the repository root is mounted and Git history is the practical undo path. Outside a Git repository, cobox explains that edits and deletions have no Git undo and asks for confirmation before continuing.

> Linux host and amd64 are required. The box design is adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).

## Security model

The intended blast radius is narrow but real: the agent can fully change the mounted project, the mounted Codex state, caches, and its per-project inner-Docker data. Everything else in the image is separate from the host system layer.

- cobox runs Docker with `--runtime=sysbox-runc`. Sysbox's user-namespace isolation is the boundary that makes autonomous operation appropriate here.
- It mounts the selected project and `${CODEX_HOME:-$HOME/.codex}` read-write at their identical host paths. The host Codex install is mounted read-only, whether it is the supported `@openai/codex` npm package or a native executable.
- It never mounts the host Docker socket, and it does not use privileged mode or host networking. The `dockerd` available in the box is an inner daemon with a project-specific volume.
- It does not mount host SSH credentials or GitHub credentials. Codex can make local commits using the read-only `.gitconfig` when present, but cobox does not give it the host's push/API credentials.
- There is no kernel-escape protection or network-egress firewall. Treat the mounted project and state as intentionally writable, review the boundary, and use cobox only on a host where that tradeoff is acceptable.

Codex's own CLI documentation warns that `--dangerously-bypass-approvals-and-sandbox` belongs only in an externally hardened or isolated environment. Here, that environment is the sysbox container; do not copy the flag into an ordinary host shell. See the official [Codex command documentation](https://learn.chatgpt.com/docs/developer-commands?surface=cli).

## Prerequisites

1. **Docker:** `docker --version` works without sudo, and `docker info -f '{{.Runtimes}}'` lists `sysbox-runc`.
2. **sysbox:** install and configure a sysbox runtime for Docker. cobox does not support a non-sysbox runtime.
3. **Host Codex:** `codex` is on `PATH`. cobox supports the official npm `@openai/codex` layout and a native executable; it mounts the resolved host installation rather than installing a second Codex inside the image.
4. **Codex state and authentication:** run Codex on the host so `${CODEX_HOME:-$HOME/.codex}` exists. Codex supports local ChatGPT or API-key authentication through `codex login`; its state and credentials live under `CODEX_HOME` (default `~/.codex`) or in the OS keyring. cobox mounts `CODEX_HOME`, but it does not mount the host OS keyring. The container therefore needs usable file-backed state under the mounted `CODEX_HOME` or a supported passed environment credential such as `OPENAI_API_KEY` or `CODEX_ACCESS_TOKEN`. A successful host login or doctor check alone does not guarantee container authentication. See the official [authentication guide](https://learn.chatgpt.com/docs/auth).

`cobox doctor` reports a failed `codex login status` as unhealthy, but launch does not block on that one check: an alternate valid authentication method, such as `OPENAI_API_KEY` or `CODEX_ACCESS_TOKEN`, may still authenticate inside the box.

## Build and install

Enable cobox from the [cotools](../../README.md) bundle, then check and build it:

```bash
cotools enable cobox
cobox doctor
cobox build
```

The image defaults to `cobox:latest` and is built locally for the current username, UID, GID, and home path. Set `COBOX_IMAGE` to use another image name. Set `COBOX_SHARE_DIR` to a directory containing the cobox `Dockerfile` when the default installed build context is not appropriate. The image includes Node 24, Python 3 + `uv`, Go 1.26.x, Rust stable, .NET 10, GitHub CLI, Git, jq, ripgrep, fd, OpenSSL, socat, and inner Docker + Compose. Codex itself is not baked in.

## Usage

```bash
cd ~/code/my-project
cobox                         # autonomous Codex in the sandbox
cobox --model gpt-5           # pass arguments through to Codex
cobox doctor                  # inspect prerequisites and state
cobox version
```

The first word `build`, `doctor`, `uninstall`, `help`, or `version` is a cobox subcommand. Any other arguments are passed to Codex after the bypass flag.

### Ports, caches, and inner Docker

The default host-to-box port range is `3000-3010`. Add ports with `COBOX_PORTS` (space-separated), or create `<repo>/.cobox/ports` with one port or range per line:

```bash
COBOX_PORTS="8080 5173" cobox
```

Services must listen on `0.0.0.0` in the box. The box starts its inner Docker daemon unless `COBOX_NO_DOCKER=1` is set; wait for `docker info` before the first inner Docker command. Shared dependency-cache volumes are `cobox-npm`, `cobox-cargo`, `cobox-go`, `cobox-uv`, and `cobox-nuget`; inner Docker data uses `cobox-docker-<project>`.

For a visual reminder, cobox tints the terminal background. Configure it with `COBOX_TINT`; set `COBOX_NO_TINT=1` to disable it. The container also receives `COBOX=1` and `COBOX_VERSION`.

## Uninstall

```bash
cobox uninstall        # image and shared caches; asks before per-project data volumes
cotools disable cobox  # remove the command link
```

Run `cobox uninstall` before `cotools uninstall`. The box uninstaller does not delete `cobox-docker-*` per-project data volumes unless explicitly confirmed.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sysbox runtime not found` | Install/configure sysbox, then confirm `docker info -f '{{.Runtimes}}'` includes `sysbox-runc`. |
| Host `codex` is not found or its layout is unsupported | Install the official npm CLI or use a native Codex executable and confirm `command -v codex`. |
| State directory is missing | Run `codex` on the host first, or set `CODEX_HOME` to an existing state directory. |
| `doctor` reports login missing | Run `codex login`, or configure an alternate valid authentication mechanism for the launch. |
| Image is missing | Run `cobox build`, or accept the interactive build prompt. |
| Inner Docker is unavailable immediately after launch | Wait until `docker info` succeeds, or use `COBOX_NO_DOCKER=1` when it is not needed. |
| Browser cannot reach an in-box service | Bind to `0.0.0.0` and publish the port with `COBOX_PORTS` or `.cobox/ports`. |
| The non-Git warning appears | Expected: either continue after acknowledging the lack of Git undo, or run from a repository. |
