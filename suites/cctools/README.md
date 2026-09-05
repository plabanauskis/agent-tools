<p>
  <a href="tools/cchat/README.md"><picture><source media="(prefers-color-scheme: dark)" srcset="tools/cchat/assets/icon-dark.svg"><img src="tools/cchat/assets/icon.svg" alt="cchat" height="56"></picture></a>
  &nbsp;&nbsp;&nbsp;
  <a href="tools/ccsession/README.md"><picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccsession/assets/icon-dark.svg"><img src="tools/ccsession/assets/icon.svg" alt="ccsession" height="56"></picture></a>
  &nbsp;&nbsp;&nbsp;
  <a href="tools/ccbox/README.md"><picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccbox/assets/icon-dark.svg"><img src="tools/ccbox/assets/icon.svg" alt="ccbox" height="56"></picture></a>
</p>

# cctools

Three small Claude Code terminal helpers, now maintained in the
[agent-tools monorepo](../../README.md). Shared installation and management code;
Claude-specific session and container behavior.

| Tool | Purpose | Dependencies | Platform |
| --- | --- | --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/cchat/assets/icon-dark.svg"><img src="tools/cchat/assets/icon.svg" alt="" width="20" height="20"></picture> [cchat](tools/cchat/README.md) | Throwaway chat in a fresh temporary directory | `claude` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccsession/assets/icon-dark.svg"><img src="tools/ccsession/assets/icon.svg" alt="" width="20" height="20"></picture> [ccsession](tools/ccsession/README.md) | fzf session picker and resume | `fzf`, `jq`, `claude` | Linux, macOS |
| <picture><source media="(prefers-color-scheme: dark)" srcset="tools/ccbox/assets/icon-dark.svg"><img src="tools/ccbox/assets/icon.svg" alt="" width="20" height="20"></picture> [ccbox](tools/ccbox/README.md) | Autonomous Claude Code in Docker + sysbox | `docker`, `sysbox-runc`, `claude` | Linux amd64 |

## Install

Requires Bash, Git, and curl. No GitHub account or sudo is needed:

```bash
curl -fsSL https://raw.githubusercontent.com/plabanauskis/agent-tools/main/install.sh | bash -s -- --suite=cctools
```

Append `--tools=cchat,ccsession` to enable only those tools. To inspect first:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/plabanauskis/agent-tools/main/install.sh
less install.sh
bash install.sh --suite=cctools --tools=cchat,ccsession
```

Or run `bash suites/cctools/install.sh` from the monorepo root for the interactive
picker. `--all` selects the suite; `--force` overrides missing dependencies and
platform checks. Selecting the lightweight tools never builds a Docker image.

For a local development install from the monorepo root:

```bash
git clone https://github.com/plabanauskis/agent-tools.git
cd agent-tools
CCTOOLS_REPO="file://$PWD" bash install.sh --suite=cctools --tools=cchat
```

The local checkout must contain the desired committed files on `main`, or set
`CCTOOLS_BRANCH`. A local install continues to update from that local repository.

## Installation and management

- `~/.local/share/cctools` is a complete monorepo clone; override `CCTOOLS_HOME`.
- `~/.local/bin` holds the enabled links plus `cctools`; override `CCTOOLS_BIN`.
- `CCTOOLS_REPO` and `CCTOOLS_BRANCH` select the upstream for a fresh clone.
- Existing clones update their configured Git upstream. Keep custom HOME/BIN
  overrides exported for management commands.

```bash
cctools list
cctools doctor [tool]
cctools enable ccbox
cctools disable cchat
cctools update
cctools version [tool]
cctools uninstall
```

`cctools update` fetches and prunes, then hard-resets a clean managed clone to its
upstream. It refuses tracked local changes. Update and uninstall refuse a source
checkout or another suite's prefix. Uninstall prompts and removes only its owned
symlinks and clone, not harness state or Docker artifacts.

For an old installation, follow the [migration guide](../../docs/migration.md).
Do not run `ccbox uninstall` merely to migrate; preserve its images and volumes.
Run it first only when intentionally removing box artifacts too.

## Security

`ccbox` runs Claude Code with `--dangerously-skip-permissions` inside a sysbox
container, with writable project and agent-state mounts. Read its
[security model](tools/ccbox/README.md#security-model) before use. `cchat` and
`ccsession` invoke the local CLI without adding that flag.

## Development and releases

From the monorepo root, `scripts/check.sh` checks all suites;
`scripts/dev-setup.sh` enables the optional root pre-push hook.
`scripts/release.sh <tool> <version>` creates per-tool `<tool>-vX.Y.Z` tags.
See the [root release documentation](../../README.md#development).

[MIT](LICENSE). Portions of ccbox adapted from
[RchGrav/claudebox](https://github.com/RchGrav/claudebox) (MIT).
