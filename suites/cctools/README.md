<div align="center">

<p>
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cchat/assets/icon-dark.svg"><img src="tools/cchat/assets/icon.svg" alt="cchat" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccsession/assets/icon-dark.svg"><img src="tools/ccsession/assets/icon.svg" alt="ccsession" height="56"></picture>
  &nbsp;&nbsp;&nbsp;
  <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccbox/assets/icon-dark.svg"><img src="tools/ccbox/assets/icon.svg" alt="ccbox" height="56"></picture>
</p>

# cctools

<p><strong>Three small, sharp Claude Code helpers for the terminal — one installer, install only what you want.</strong></p>

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Built for Claude Code" src="https://img.shields.io/badge/built%20for-Claude%20Code-D97757">
  <img alt="Install: no sudo · no daemons" src="https://img.shields.io/badge/install-no%20sudo%20%C2%B7%20no%20daemons-555">
</p>

</div>

Three small, sharp helpers for working with [Claude Code](https://claude.com/claude-code)
in the Linux/macOS terminal — bundled behind one installer and a tiny management
command. Install only what you want; uninstall leaves your machine exactly as it was.

| Tool | What it does | Deps | Platform |
|------|--------------|------|----------|
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cchat/assets/icon-dark.svg"><img src="tools/cchat/assets/icon.svg" alt="" width="20"></picture> **cchat** | Opens Claude Code in a fresh ephemeral `/tmp` dir for throwaway chats | `claude` | linux, macos |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccsession/assets/icon-dark.svg"><img src="tools/ccsession/assets/icon.svg" alt="" width="20"></picture> **ccsession** | `fzf` picker to list and resume any Claude Code session without `cd`-ing | `fzf`, `jq`, `claude` | linux, macos |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccbox/assets/icon-dark.svg"><img src="tools/ccbox/assets/icon.svg" alt="" width="20"></picture> **ccbox** | Sandboxed autonomous Claude Code via Docker + sysbox (path-identical host mirror) | `docker`, `sysbox-ce`, `claude` | linux (amd64) |

cchat and ccsession are featherweight and portable; ccbox is heavy (a ~5 GB Docker
image) and Linux-only. The installer is dep-aware and opt-in, so wanting `ccsession`
never drags you into ccbox's Docker world.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/plabanauskis/cctools/main/install.sh | bash
```

Prefer to read before you run (recommended):

```bash
curl -fsSL -O https://raw.githubusercontent.com/plabanauskis/cctools/main/install.sh
less install.sh
bash install.sh            # interactive picker
bash install.sh --all      # or: --tools=cchat,ccsession   /   --force
```

## What gets installed (and how to remove it)

No sudo. Nothing in `/usr` or `/etc`; no daemons. The installer touches **only two
user-owned locations** (the same pattern as `rustup`, `nvm`, and Claude Code's own
installer):

- `~/.local/share/cctools` — a git clone of this repo (the single source of truth).
  Override with `CCTOOLS_HOME`.
- `~/.local/bin` — one symlink per enabled command, plus `cctools`.

To remove everything:

```bash
ccbox uninstall      # FIRST, only if you used ccbox — removes its image/volumes
cctools uninstall    # removes the symlinks + the clone; prompts first
```

Because nothing else was ever created, your host is pristine afterward.

## Managing tools

Tools run by their own names (`cchat`, `ccsession`, `ccbox`). `cctools` is for
lifecycle only:

```bash
cctools list                 # tools, enabled state, versions, platform + dep status
cctools doctor [tool]        # check deps + platform
cctools enable <tool>        # symlink the tool's command(s) into ~/.local/bin
cctools disable <tool>       # remove them
cctools update               # git pull the clone, then re-link enabled tools
cctools version [tool]       # versions from VERSION files
```

If `~/.local/bin` isn't on your `PATH`, the installer prints the exact line to add.

## The tools

- [cchat](tools/cchat/README.md) — throwaway chats in a fresh temp dir.
- [ccsession](tools/ccsession/README.md) — `fzf` session picker + resume.
- [ccbox](tools/ccbox/README.md) — sandboxed autonomous Claude Code.

## Security

ccbox runs Claude Code with `--dangerously-skip-permissions` inside a sysbox
container that mirrors your environment but isolates the system layer. Read its
[security model and threat model](tools/ccbox/README.md#security-model) before
using it. cchat and ccsession run no privileged operations.

## Development

```bash
scripts/dev-setup.sh   # wire up the pre-push hook (runs scripts/check.sh)
scripts/check.sh       # shellcheck + shfmt + all tool tests + gated ccbox smoke
```

Per-tool releases: `scripts/release.sh <tool> <version>` (tags `<tool>-vX.Y.Z`).

## License

[MIT](LICENSE). Portions of ccbox adapted from
[RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).
