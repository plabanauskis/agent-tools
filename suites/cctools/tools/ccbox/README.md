<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="ccbox" width="320">
</picture>

<p><strong>Give Claude Code full control of your project, never of your computer.</strong></p>

<p>
  Point it at any repo and it edits files, runs commands, and runs your tests without stopping to
  ask. Everything happens inside a secure sandbox that mirrors your real setup — so even a bad
  mistake can't reach your operating system or your other files.
</p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <a href="https://github.com/plabanauskis/cctools/releases"><img alt="Latest release: 1.1.0" src="https://img.shields.io/badge/release-1.1.0-D97757"></a>
  <img alt="Platform: Linux · amd64" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20amd64-555">
  <img alt="Built for Claude Code" src="https://img.shields.io/badge/built%20for-Claude%20Code-D97757">
</p>

</div>

One command drops you into the normal interactive Claude Code **terminal chat** running inside
a Docker container with `--dangerously-skip-permissions`. Run it from a git repository (it
mounts the repo root), or from any other directory after a one-time warning — outside a repo
there's no git history to undo the agent's edits. The agent works fully autonomously (no
per-action prompts) on your project, can run its own `docker compose` stack and test suite, and
**cannot make system-wide changes that damage the host OS**.

The box is a **path-identical mirror** of your environment: it runs as *you*, at your real
`$HOME`, with the repo at its real path, your `~/.claude` mounted read-write, and your host
`claude` binary mounted read-only. So memories, plugins, config, and commit identity all
behave exactly as on the host — only the system layer is isolated.

> Linux host only. `amd64` assumed (see [Architecture notes](#architecture-notes)).
> Portions adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).

---

## Security model

The threat model is deliberately narrow and one-directional: **protect the host system.**
The agent has total freedom *inside* the box; it just can't change the host OS.

- **The container isolates the system layer.** The OS, installed packages, `/usr`, `/etc`,
  `/var`, and anything **outside the explicit mounts** are the image's own and ephemeral.
  ccbox runs under the **sysbox** runtime (`--runtime=sysbox-runc`), whose user namespaces map
  container root to an unprivileged host user — so even a full Docker engine inside the box
  can't touch the host.
- **No host escalation paths.** Never mounts the host Docker socket, never uses `--privileged`
  or `--network=host`. Inner Docker is a real `dockerd` running *inside* the sandbox.
- **In-scope blast radius (the agent can change these — by design):**
  - the **mounted repo** (edits/commits are real — git history is your undo),
  - **`~/.claude`** read-write (so memories, plugins, config, and credential refresh persist
    to the host — this is the point),
  - the project's **inner-Docker data volume**.
- **Out of reach:** other repos, other home contents (`~/.ssh`, other projects — not
  mounted), and your GitHub account (no GitHub credentials are mounted, so the agent can
  commit locally but **cannot push** from the box).
- **Honest caveat:** because `~/.claude` is read-write, the agent *could* corrupt your host
  Claude config/plugins/credentials. That is the price of memory-persistence, and is accepted.

This is **not** kernel-escape protection (no microVM/KVM) and there is **no network egress
firewall** — neither is in scope.

---

## Prerequisites

You (the operator) do these once, by hand.

### A. Docker

`docker --version` works **without sudo** (your user is in the `docker` group).

### B. Host Claude Code

Install Claude Code on the host (the **native installer** layout, under
`~/.local/share/claude/`) and complete the subscription login so
`~/.claude/.credentials.json` exists. ccbox **mounts your host `claude` binary** into the box,
so the box always runs your exact host version — there is nothing to install or update inside
the box. (Headless Linux stores creds in `~/.claude/.credentials.json`. If your system uses a
keyring instead, use the `ANTHROPIC_API_KEY` fallback — see Troubleshooting.)

### C. sysbox-ce (enables safe inner Docker)

1. Ensure standard rootful Docker is running and your kernel is ≥ 5.12 (gives ID-mapped
   mounts; check with `uname -r`).
2. Download the latest `sysbox-ce` `.deb` for your distro/arch from
   <https://github.com/nestybox/sysbox/releases>.
3. Install:

   ```bash
   sudo apt-get update
   sudo apt-get install -y ./sysbox-ce_*.deb
   ```

   The installer registers the `sysbox-runc` runtime with Docker and restarts the daemon.
4. Verify:

   ```bash
   docker info -f '{{.Runtimes}}'   # must list sysbox-runc
   ```

---

## Install

ccbox is part of the [cctools](../../README.md) bundle (Linux/amd64 only):

```bash
cctools enable ccbox      # symlinks the 'ccbox' command into ~/.local/bin
ccbox doctor              # check prerequisites (Docker, sysbox-ce, host claude, login)
ccbox build               # build the container image, mirroring your user (~5 min, ~5GB)
```

The `ccbox` command is a symlink into the bundle clone; `ccbox build` finds the
`Dockerfile` next to the script. The 5 GB image is built locally by `ccbox build`
(so it mirrors your username/UID/GID/home) and is never shipped.

**Toolchains baked in:** Node 24 LTS, Python 3 + `uv`, Go 1.26.x, Rust (stable), .NET 10 LTS,
plus `git`, `gh`, `jq`, `ripgrep`, `fd`, `openssl`, `socat`, and an inner Docker Engine +
Compose v2. (`claude` itself is **not** baked in — it's mounted from the host.) Versions are
`ARG`s in the `Dockerfile`; override with `--build-arg NODE_MAJOR=…` etc.

## Uninstall

```bash
ccbox uninstall          # removes the image + caches; PROMPTS before data volumes
cctools disable ccbox    # removes the 'ccbox' command symlink
```

`ccbox uninstall` never deletes your per-project database volumes (`ccbox-docker-*`)
without an explicit yes. Run it **before** `cctools uninstall` — the bundle
uninstaller never touches Docker data. (If you used ccbox 1.x, it also offers to
remove the now-unused `~/.config/ccbox` GitHub App config.)

---

## Usage

From inside a git repository (or any other directory — you'll be warned first, since there's
no git history to undo the agent's edits there):

```bash
cd ~/code/my-project
ccbox
```

You land in the normal Claude Code chat — but every shell action runs **without a permission
prompt**, inside the sandbox, against your live-mounted repo. Because the box mirrors your
real paths, the agent's **memories and session history land in the same project bucket as your
host** (`~/.claude/projects/<real-repo-path>/`), and your **plugins load exactly as on the
host**.

- **Pass args straight through to Claude:** `ccbox --model opus`
- **Commits are authored as you** (from `~/.gitconfig`); **pushes don't work** in the box (no
  GitHub creds) — push from the host.
- **Quick, no-Docker session** (skips starting the inner daemon, faster startup):
  `CCBOX_NO_DOCKER=1 ccbox`
- **Spot a sandbox session at a glance:** the terminal background is tinted for the session
  (override `CCBOX_TINT`, disable `CCBOX_NO_TINT=1`); `CCBOX=1` is also exported for scripts.
- **Inside the box, the inner Docker daemon starts in the background.** Before your first
  `docker` / `docker compose` call, wait a few seconds for it to come up:

  ```bash
  until docker info >/dev/null 2>&1; do sleep 1; done
  docker compose up -d
  ```

### Ports (host browser → in-box app)

A default range (`3000-3010`) is published. Add more per session with `CCBOX_PORTS` (space
separated) or per repo via `<repo>/.ccbox/ports` (one port/range per line):

```bash
CCBOX_PORTS="8080 5173" ccbox
```

The in-box service must bind `0.0.0.0` (compose default), then open `http://localhost:<port>`
in your host browser.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Claude asks you to log in instead of using mounted creds | Ensure `~/.claude/.credentials.json` exists (Prereq B) and is writable. If your host stores creds in a keyring, run with `ANTHROPIC_API_KEY=… ccbox`. |
| `host 'claude' not found on PATH` | Install Claude Code on the host (Prereq B); confirm `command -v claude` works. |
| `host claude … isn't under ~/.local/share/claude` | You installed `claude` via npm-global, which this mount doesn't support. Use the native installer, or open an issue. |
| Files created in the box are owned by the wrong UID | Rebuild so the image mirrors your account: `ccbox build` (passes your username/UID/GID/home). |
| `ccbox: sysbox runtime not found` | Install sysbox-ce (Prereq C); verify with `docker info -f '{{.Runtimes}}'`. |
| `docker` / `docker compose` "cannot connect" right after launch | The inner daemon is still starting — wait (see Usage). |
| In-box web app unreachable from host browser | The service must bind `0.0.0.0` and its port must be published (see Ports). |
| `ccbox` warns the directory is not a git repository | Expected outside a repo: there's no git history to undo the agent's edits. Press `y` to continue (the whole dir is mounted read-write), or `cd` into a git repo. |

---

## Architecture notes

- **Image:** Debian bookworm + language toolchains + inner Docker. `claude`, your config,
  plugins, and memories all come **live from the host** at run time — the image carries none
  of them, so there is no version skew and nothing to update inside the box.
- **`amd64` assumed.** The host native-installer `claude` binary is amd64; on `arm64` you'd
  also need to adjust the Go tarball arch (Node/Docker/.NET handle arm64 via their repos).
- **Native-installer layout assumed** for `claude` (`~/.local/share/claude/versions/<v>`); an
  npm-global install isn't mountable this way.
- See [`docs/superpowers/specs/2026-06-22-ccbox-redesign-design.md`](docs/superpowers/specs/2026-06-22-ccbox-redesign-design.md)
  for the full design rationale and threat model.
