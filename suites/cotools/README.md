# cotools

Three focused Codex terminal helpers, now maintained in the
[agent-tools monorepo](../../README.md). Shared installation and management code;
Codex-specific session and container behavior.

| Tool | Purpose | Dependencies | Platform |
| --- | --- | --- | --- |
| [cochat](tools/cochat/README.md) | Throwaway chat in a fresh temporary directory | `codex` | Linux, macOS |
| [cosession](tools/cosession/README.md) | fzf session picker and resume | `fzf`, `jq`, `codex` | Linux, macOS |
| [cobox](tools/cobox/README.md) | Autonomous Codex in Docker + sysbox | `docker`, `sysbox-runc`, `codex` | Linux amd64 |

## Install

The repository is private. Use authenticated Git, not an unauthenticated raw URL:

```bash
gh auth login
gh auth setup-git
gh repo clone plabanauskis/agent-tools
cd agent-tools
bash install.sh --suite=cotools --tools=cochat,cosession
```

Or run `bash suites/cotools/install.sh` from the monorepo root for the interactive
picker. `--all` selects the suite; `--force` overrides missing dependencies and
platform checks. Selecting the lightweight tools never builds a Docker image.

For a local development install:

```bash
COTOOLS_REPO="file://$PWD" bash install.sh --suite=cotools --tools=cochat
```

The local checkout must contain the desired committed files on `main`, or set
`COTOOLS_BRANCH`. A local install continues to update from that local repository.

## Installation and management

- `~/.local/share/cotools` is a complete monorepo clone; override `COTOOLS_HOME`.
- `~/.local/bin` holds the enabled links plus `cotools`; override `COTOOLS_BIN`.
- `COTOOLS_REPO` and `COTOOLS_BRANCH` select the upstream for a fresh clone.
- Existing clones update their configured Git upstream. Keep custom HOME/BIN
  overrides exported for management commands.

```bash
cotools list
cotools doctor [tool]
cotools enable cobox
cotools disable cochat
cotools update
cotools version [tool]
cotools uninstall
```

`cotools update` fetches and prunes, then hard-resets a clean managed clone to its
upstream. It refuses tracked local changes. Update and uninstall refuse a source
checkout or another suite's prefix. Uninstall prompts and removes only its owned
symlinks and clone, not harness state or Docker artifacts.

For an old installation, follow the [migration guide](../../docs/migration.md).
Do not run `cobox uninstall` merely to migrate; preserve its images and volumes.
Run it first only when intentionally removing box artifacts too.

## Security

`cobox` runs Codex with `--dangerously-bypass-approvals-and-sandbox` only inside
its external sysbox isolation boundary, with writable project and Codex-state
mounts. Read the [security model](tools/cobox/README.md#security-model).
The local `cochat` and `cosession` wrappers do not add that flag.

## Development and releases

From the monorepo root, `scripts/check.sh` checks all suites;
`scripts/dev-setup.sh` enables the optional root pre-push hook.
`scripts/release.sh <tool> <version>` creates per-tool `<tool>-vX.Y.Z` tags.
See the [root release documentation](../../README.md#development).

[MIT](LICENSE). Portions of the box design adapted from
[RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).
This project is not affiliated with or endorsed by OpenAI.
