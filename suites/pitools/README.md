# pitools

Three focused Pi terminal helpers, now maintained in the
[agent-tools monorepo](../../README.md). Shared installation and management code;
Pi-specific session and container behavior.

| Tool | Purpose | Dependencies | Platform |
| --- | --- | --- | --- |
| [pichat](tools/pichat/README.md) | Throwaway chat in a fresh temporary directory | `pi` | Linux, macOS |
| [pisession](tools/pisession/README.md) | fzf session picker and resume | `fzf`, `jq`, `pi` | Linux, macOS |
| [pibox](tools/pibox/README.md) | Pi in Docker + sysbox | `docker`, `sysbox-runc`, `pi` | Linux amd64 |

## Install

The repository is private. Use authenticated Git, not an unauthenticated raw URL:

```bash
gh auth login
gh auth setup-git
gh repo clone plabanauskis/agent-tools
cd agent-tools
bash install.sh --suite=pitools --tools=pichat,pisession
```

Or run `bash suites/pitools/install.sh` from the monorepo root for the interactive
picker. `--all` selects the suite; `--force` overrides missing dependencies and
platform checks. Selecting the lightweight tools never builds a Docker image.

For a local development install:

```bash
PITOOLS_REPO="file://$PWD" bash install.sh --suite=pitools --tools=pichat
```

The local checkout must contain the desired committed files on `main`, or set
`PITOOLS_BRANCH`. A local install continues to update from that local repository.

## Installation and management

- `~/.local/share/pitools` is a complete monorepo clone; override `PITOOLS_HOME`.
- `~/.local/bin` holds the enabled links plus `pitools`; override `PITOOLS_BIN`.
- `PITOOLS_REPO` and `PITOOLS_BRANCH` select the upstream for a fresh clone.
- Existing clones update their configured Git upstream. Keep custom HOME/BIN
  overrides exported for management commands.

```bash
pitools list
pitools doctor [tool]
pitools enable pibox
pitools disable pichat
pitools update
pitools version [tool]
pitools uninstall
```

`pitools update` fetches and prunes, then hard-resets a clean managed clone to its
upstream. It refuses tracked local changes. Update and uninstall refuse a source
checkout or another suite's prefix. Uninstall prompts and removes only its owned
symlinks and clone, not harness state or Docker artifacts.

For an old installation, follow the [migration guide](../../docs/migration.md).
Do not run `pibox uninstall` merely to migrate; preserve its images and volumes.
Run it first only when intentionally removing box artifacts too.

## Pi-specific behavior and security

- Sessions are JSONL trees under `${PI_CODING_AGENT_SESSION_DIR:-${PI_CODING_AGENT_DIR:-~/.pi/agent}/sessions}`.
- `pisession` retains Pi header, name, message, model-change, and version parsing.
- `pibox` does not invent or pass a bypass flag; the entire Pi process runs in
  the sysbox-backed container.
- It mounts `PI_CODING_AGENT_DIR` and, when needed, a custom
  `PI_CODING_AGENT_SESSION_DIR`, retaining the original mount and provider-env
  allowlist behavior. The host installation is mounted read-only.

Projects and agent state are writable. Read the
[security model](tools/pibox/README.md#security-model) before use.

## Development and releases

From the monorepo root, `scripts/check.sh` checks all suites;
`scripts/dev-setup.sh` enables the optional root pre-push hook.
`scripts/release.sh <tool> <version>` creates per-tool `<tool>-vX.Y.Z` tags.
See the [root release documentation](../../README.md#development).

[MIT](LICENSE). Portions of the box design adapted from
[RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).
This project is independent of the Pi maintainers and Earendil Works.
