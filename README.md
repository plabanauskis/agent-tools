<div align="center">

<p>
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cochat/assets/icon-dark.svg"><img src="tools/cochat/assets/icon.svg" alt="cochat" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cosession/assets/icon-dark.svg"><img src="tools/cosession/assets/icon.svg" alt="cosession" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cobox/assets/icon-dark.svg"><img src="tools/cobox/assets/icon.svg" alt="cobox" height="56"></picture>
</p>

# cotools

<p><strong>Three small terminal helpers for Codex — one installer, install only what you want.</strong></p>

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Built for Codex" src="https://img.shields.io/badge/built%20for-Codex-10A37F">
  <img alt="Install: no sudo · no daemons" src="https://img.shields.io/badge/install-no%20sudo%20%C2%B7%20no%20daemons-555">
</p>

</div>

Three focused helpers for working with the [Codex CLI](https://learn.chatgpt.com/docs/developer-commands?surface=cli) in a Linux or macOS terminal. They are bundled behind one installer and a small management command; install only the tools you need.

| Tool | What it does | Dependencies | Platform |
| --- | --- | --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cochat/assets/icon-dark.svg"><img src="tools/cochat/assets/icon.svg" alt="" width="20"></picture> [**cochat**](tools/cochat/README.md) | Opens Codex in a fresh temporary directory for a throwaway chat | `codex` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cosession/assets/icon-dark.svg"><img src="tools/cosession/assets/icon.svg" alt="" width="20"></picture> [**cosession**](tools/cosession/README.md) | Finds and resumes local Codex sessions with an `fzf` picker | `fzf`, `jq`, `codex` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cobox/assets/icon-dark.svg"><img src="tools/cobox/assets/icon.svg" alt="" width="20"></picture> [**cobox**](tools/cobox/README.md) | Runs autonomous Codex against a mounted project inside Docker + sysbox | `docker`, `sysbox-runc`, `codex` | Linux (amd64) |

`cochat` and `cosession` are lightweight, portable shell tools. `cobox` is deliberately heavier: it needs a locally built Docker image and Linux's sysbox runtime. The installer is dependency-aware and opt-in, so selecting `cosession` does not install or build the box.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/plabanauskis/cotools/main/install.sh | bash
```

Read the installer first if you prefer:

```bash
curl -fsSL -O https://raw.githubusercontent.com/plabanauskis/cotools/main/install.sh
less install.sh
bash install.sh                       # interactive picker
bash install.sh --all                 # every eligible tool
bash install.sh --tools=cochat,cosession
```

The installer needs Git. It chooses tools interactively with a TTY; otherwise it enables only tools supported by the host and with available dependencies. `--force` creates links even when a dependency is missing.

## What gets installed

No sudo, no `/usr` or `/etc` changes, and no daemons. The installer writes only these user-owned locations:

- `~/.local/share/cotools` — the Git clone, the single source of truth. Override with `COTOOLS_HOME`.
- `~/.local/bin` — the `cotools` link and one link per enabled command. Override with `COTOOLS_BIN`.

For a mirror or fork, set `COTOOLS_REPO` to the clone URL and `COTOOLS_BRANCH`
to the branch before running `install.sh`; their defaults are this repository
and `main`.

If the bin directory is not on `PATH`, the installer prints the exact export to add to the shell startup file.

To remove the suite, remove box runtime artifacts first if applicable:

```bash
cobox uninstall       # first, if cobox was used: image and caches; data stays opt-in
cotools uninstall     # links and the cotools clone; prompts first
```

## Managing tools

Run tools directly; use `cotools` for their lifecycle:

```bash
cotools list                 # tools, state, versions, platform and dependency status
cotools doctor [tool]        # dependency and platform checks
cotools enable <tool>        # link a tool into ~/.local/bin
cotools disable <tool>       # remove its link
cotools update               # update the managed clone and re-link enabled tools
cotools version [tool]       # bundle or per-tool version
cotools uninstall            # remove links and clone after confirmation
```

`cotools update` treats its installed prefix as a managed mirror: when tracked
files are clean, it fetches and prunes, then hard-resets to the configured
upstream branch. This also handles rewritten upstream history. It refuses to
overwrite tracked local changes; untracked files are left untouched.

## Security

`cochat` and `cosession` only invoke the local Codex CLI. `cobox` is different: it deliberately gives Codex autonomous operation inside a sysbox-isolated Docker container while mounting the selected project and Codex state. It uses Codex's `--dangerously-bypass-approvals-and-sandbox` flag only because sysbox is the external isolation boundary. Read the complete [cobox security model](tools/cobox/README.md#security-model) before using it.

## Development and releases

```bash
scripts/dev-setup.sh   # install the pre-push hook
scripts/check.sh       # shell checks, formatting, tests, assets, and gated cobox smoke test
```

Release one tool with `scripts/release.sh <tool> <version>`; tags use `<tool>-vX.Y.Z`. The normal check suite runs without a box image, while the final cobox smoke test runs only when both sysbox and the image are available.

## License and attribution

[MIT](LICENSE). Portions of the cobox design are adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).

cotools is an independent open-source project. It is not affiliated with or endorsed by OpenAI.
