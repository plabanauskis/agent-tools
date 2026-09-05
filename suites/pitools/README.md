<div align="center">

<p>
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pichat/assets/icon-dark.svg"><img src="tools/pichat/assets/icon.svg" alt="pichat" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pisession/assets/icon-dark.svg"><img src="tools/pisession/assets/icon.svg" alt="pisession" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pibox/assets/icon-dark.svg"><img src="tools/pibox/assets/icon.svg" alt="pibox" height="56"></picture>
</p>

# pitools

<p><strong>Three small terminal helpers for Pi — one installer, install only what you want.</strong></p>

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Built for Pi" src="https://img.shields.io/badge/built%20for-Pi-4B607C">
  <img alt="Install: no sudo · no daemons" src="https://img.shields.io/badge/install-no%20sudo%20%C2%B7%20no%20daemons-555">
</p>

</div>

Three focused helpers for working with the [Pi coding agent](https://pi.dev) in a Linux or macOS terminal. The suite is a direct Pi port of the established cctools/cotools design: the installer, manager, lifecycle, tests, and most shell behavior are shared; only harness-specific state, sessions, launching, and branding differ.

| Tool | What it does | Dependencies | Platform |
| --- | --- | --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pichat/assets/icon-dark.svg"><img src="tools/pichat/assets/icon.svg" alt="" width="20"></picture> [**pichat**](tools/pichat/README.md) | Opens Pi in a fresh temporary directory for a throwaway chat | `pi` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pisession/assets/icon-dark.svg"><img src="tools/pisession/assets/icon.svg" alt="" width="20"></picture> [**pisession**](tools/pisession/README.md) | Finds and resumes Pi sessions from every working directory | `fzf`, `jq`, `pi` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/pibox/assets/icon-dark.svg"><img src="tools/pibox/assets/icon.svg" alt="" width="20"></picture> [**pibox**](tools/pibox/README.md) | Runs Pi against a mounted project inside Docker + sysbox | `docker`, `sysbox-runc`, `pi` | Linux (amd64) |

`pichat` and `pisession` are lightweight shell tools. `pibox` is deliberately heavier: it needs a locally built Docker image and Linux's sysbox runtime. Selecting one of the lightweight tools never installs or builds the box.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/plabanauskis/pitools/main/install.sh | bash
```

Prefer to inspect the installer first:

```bash
curl -fsSL -O https://raw.githubusercontent.com/plabanauskis/pitools/main/install.sh
less install.sh
bash install.sh                       # interactive picker
bash install.sh --all                 # every eligible tool
bash install.sh --tools=pichat,pisession
```

For development, install directly from a local checkout with `PITOOLS_REPO="file://$PWD"`. `--force` creates links even when a platform requirement or dependency is missing.

## What gets installed

No sudo, no `/usr` or `/etc` changes, and no host daemons. The installer writes only these user-owned locations:

- `~/.local/share/pitools` — a Git clone of this repository. Override with `PITOOLS_HOME`.
- `~/.local/bin` — the `pitools` link and one link per enabled command. Override with `PITOOLS_BIN`.

Set `PITOOLS_REPO` to a mirror, fork, or local clone and `PITOOLS_BRANCH` to its branch. If the bin directory is not on `PATH`, the installer prints the exact export to add.

Remove box runtime artifacts before removing the suite:

```bash
pibox uninstall       # first, if used: image and caches; project data stays opt-in
pitools uninstall     # links and the managed clone; prompts first
```

## Managing tools

Run tools directly; use `pitools` for lifecycle operations:

```bash
pitools list                 # tools, state, versions, platform and dependency status
pitools doctor [tool]        # dependency and platform checks
pitools enable <tool>        # link a tool into ~/.local/bin
pitools disable <tool>       # remove its link
pitools update               # sync the managed clone and re-link enabled tools
pitools version [tool]       # bundle or per-tool version
pitools uninstall            # remove links and clone after confirmation
```

`pitools update` fetches and prunes, then hard-resets a clean managed clone to its configured upstream. This tolerates rewritten history but refuses to overwrite tracked local changes; untracked files remain untouched.

## Pi-specific behavior

- Pi sessions live under `${PI_CODING_AGENT_SESSION_DIR:-${PI_CODING_AGENT_DIR:-~/.pi/agent}/sessions}` as JSONL trees. `pisession` parses Pi headers, names, messages, model changes, and format versions directly.
- Pi runs tools with all permissions by default. `pibox` does not invent or pass a bypass flag; the whole Pi process runs inside the sysbox-backed container, matching Pi's documented whole-process containerization pattern.
- `pibox` mounts `${PI_CODING_AGENT_DIR:-~/.pi/agent}` read-write, mounts a custom `PI_CODING_AGENT_SESSION_DIR` when needed, and mounts the resolved host Pi package read-only.

## Security

`pichat` and `pisession` invoke the local Pi CLI. `pibox` gives Pi full control of the mounted project and agent state inside a sysbox-isolated Docker container. It never mounts the host Docker socket, SSH directory, or GitHub CLI credentials. Read the complete [pibox security model](tools/pibox/README.md#security-model) before use.

## Development and releases

```bash
scripts/dev-setup.sh   # install the pre-push hook
scripts/check.sh       # shell checks, tests, assets, and gated pibox smoke test
```

Release one tool with `scripts/release.sh <tool> <version>`; tags use `<tool>-vX.Y.Z`.

## License and attribution

[MIT](LICENSE). The suite was ported from the sibling cctools/cotools repositories. Portions of the pibox design are adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).

pitools is independent and is not affiliated with or endorsed by the Pi maintainers or Earendil Works.
