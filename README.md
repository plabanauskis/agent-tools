# agent-tools

Small terminal helpers for **Claude Code, Codex, and Pi**. One development home,
shared lifecycle infrastructure, three independently installable suites.

| Purpose | Claude Code | Codex | Pi |
| --- | --- | --- | --- |
| Throwaway chat in a fresh temporary directory | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cctools/tools/cchat/assets/icon-dark.svg"><img src="suites/cctools/tools/cchat/assets/icon.svg" alt="" width="32" height="32"></picture> [cchat](suites/cctools/tools/cchat/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cotools/tools/cochat/assets/icon-dark.svg"><img src="suites/cotools/tools/cochat/assets/icon.svg" alt="" width="32" height="32"></picture> [cochat](suites/cotools/tools/cochat/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/pitools/tools/pichat/assets/icon-dark.svg"><img src="suites/pitools/tools/pichat/assets/icon.svg" alt="" width="32" height="32"></picture> [pichat](suites/pitools/tools/pichat/README.md) |
| Find and resume sessions with fzf | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cctools/tools/ccsession/assets/icon-dark.svg"><img src="suites/cctools/tools/ccsession/assets/icon.svg" alt="" width="32" height="32"></picture> [ccsession](suites/cctools/tools/ccsession/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cotools/tools/cosession/assets/icon-dark.svg"><img src="suites/cotools/tools/cosession/assets/icon.svg" alt="" width="32" height="32"></picture> [cosession](suites/cotools/tools/cosession/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/pitools/tools/pisession/assets/icon-dark.svg"><img src="suites/pitools/tools/pisession/assets/icon.svg" alt="" width="32" height="32"></picture> [pisession](suites/pitools/tools/pisession/README.md) |
| Path-identical Docker + sysbox sandbox | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cctools/tools/ccbox/assets/icon-dark.svg"><img src="suites/cctools/tools/ccbox/assets/icon.svg" alt="" width="32" height="32"></picture> [ccbox](suites/cctools/tools/ccbox/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/cotools/tools/cobox/assets/icon-dark.svg"><img src="suites/cotools/tools/cobox/assets/icon.svg" alt="" width="32" height="32"></picture> [cobox](suites/cotools/tools/cobox/README.md) | <picture><source media="(prefers-color-scheme: dark)" srcset="suites/pitools/tools/pibox/assets/icon-dark.svg"><img src="suites/pitools/tools/pibox/assets/icon.svg" alt="" width="32" height="32"></picture> [pibox](suites/pitools/tools/pibox/README.md) |
| Manage installed tools | [cctools](suites/cctools/README.md) | [cotools](suites/cotools/README.md) | [pitools](suites/pitools/README.md) |

Chat/session tools support Linux and macOS. Boxes require Linux amd64, Docker,
sysbox, and a separately built image. Installing a session picker never builds
an image or installs a harness.

## Install while this repository is private

Authenticate once, clone the complete repository, then choose a suite:

```bash
gh auth login
gh auth setup-git
gh repo clone plabanauskis/agent-tools
cd agent-tools

bash install.sh --suite=pitools --tools=pichat,pisession
# Or:
bash install.sh --suite=cotools --tools=cochat,cosession
bash install.sh --suite=cctools --tools=cchat,ccsession
```

The installer uses authenticated Git over HTTPS. An unauthenticated raw GitHub
`curl | bash` command does **not** work for this private repository. SSH users
can set the corresponding suite's repository override to
`git@github.com:plabanauskis/agent-tools.git`.

For offline development, clone from your local committed checkout instead:

```bash
PITOOLS_REPO="file://$PWD" bash install.sh --suite=pitools --tools=pichat
```

This installs committed files, not uncommitted working-tree edits. The installed
clone's upstream is then your local repository; updates require that path to
remain available. For a non-`main` branch, also set `PITOOLS_BRANCH`.

Existing legacy installation? Follow [the migration guide](docs/migration.md)
first. The new installer refuses to overwrite an unmanaged or legacy directory.

### Selection and configuration

- `--suite=cctools|cotools|pitools` is required by the root installer.
- `--tools=a,b` enables only those tools; `--all` selects the whole chosen suite.
- No selection: interactive picker with a TTY, otherwise eligible tools only.
- `--force` allows links despite missing dependencies/platform support.
- Suite-specific entrypoints remain available: `bash suites/pitools/install.sh`.

| Suite | Clone prefix override | Bin directory override | Upstream overrides |
| --- | --- | --- | --- |
| cctools | `CCTOOLS_HOME` | `CCTOOLS_BIN` | `CCTOOLS_REPO`, `CCTOOLS_BRANCH` |
| cotools | `COTOOLS_HOME` | `COTOOLS_BIN` | `COTOOLS_REPO`, `COTOOLS_BRANCH` |
| pitools | `PITOOLS_HOME` | `PITOOLS_BIN` | `PITOOLS_REPO`, `PITOOLS_BRANCH` |

Defaults are `~/.local/share/<suite>`, `~/.local/bin`, this repository, and `main`.
Each prefix contains a complete monorepo clone and an ignored ownership marker
`.agent-tools-suite`. Prefixes must remain separate. There is no independently
installed shared core and no cross-prefix runtime dependency.

Keep custom `*_HOME`/`*_BIN` settings in your shell environment when using
management commands. Existing harness-specific state/configuration variables
are unchanged. Selecting a new `*_REPO` or `*_BRANCH` applies to a fresh install;
existing managed clones update their configured Git upstream.

## Manage tools

```bash
pitools list
pitools doctor
pitools enable pibox       # only links it; building the image is separate
pitools disable pichat
pitools update
pitools version
pitools uninstall         # prompts; removes only owned links and this prefix
```

Replace `pitools` with `cctools` or `cotools` for the other suites. Update fetches
and resets a clean installer-managed clone to its upstream (including rewritten
upstream history), refusing staged or unstaged tracked edits. Do not use an
installed prefix for development or local commits. Update/uninstall refuse a
development checkout or another suite's prefix.

Uninstall does not delete sessions, credentials, projects, Docker images, or
volumes. Use a box's own `uninstall` command **only** when you want its runtime
artifacts removed; check that tool's documentation for data-preservation options.

## Architecture

```text
bin/                  shared manager entrypoint + suite-name symlinks
lib/                  common manifests, installer, manager, release functions
scripts/              unified checks, developer setup, per-tool release entrypoint
suites/<suite>/        small compatibility entrypoints, suite docs and tests
  tools/<tool>/       harness-specific scripts, manifests, versions, assets, docs
docker/               shared Codex/Pi Dockerfile (suite paths link here)
tests/                cross-suite lifecycle and repository contracts
```

Shared changes land once and are tested against all suites. Harness session
parsers, session-picker implementations, launch arguments, authentication,
container mounts, and state/volume names remain separate in this first
consolidation. The tiny chat scripts remain standalone. Further session UI or
container helper extraction can happen independently, without a big rewrite.

The Claude image retains its distinct recipe. The Codex/Pi recipe is shared,
but their images, entrypoints, credentials and Docker volumes are not merged.
Read each box's security model before use: host project and agent state mounts
are writable; a container is not a guarantee against all harmful actions.

## Development

```bash
scripts/check.sh          # shell syntax, shellcheck, shfmt, all existing + shared tests
scripts/dev-setup.sh      # optional: enable the root pre-push check hook
AGENT_TOOLS_SMOKE=1 scripts/check.sh  # opt into live smoke only when runtime/images exist
```

Checks require Bash, Git, jq, shellcheck, shfmt, ripgrep, ImageMagick, and xmllint.
On Debian/Ubuntu, the last two are provided by `imagemagick` and `libxml2-utils`.
Tests use temporary repositories and fake harness/container commands. Live
Docker smoke is explicitly opt-in and never builds an image automatically.

Release tools independently:

```bash
scripts/release.sh pichat 1.1.0
```

The helper requires a clean tree, updates the tool's version/changelog (and an
embedded box version when applicable), commits, and creates `<tool>-vX.Y.Z`.
Complete the generated changelog TODO before publication: amend the local
commit, then recreate the **unpublished** tag at that commit. Do not rewrite
published tags. `--gh` explicitly pushes and creates a **draft** GitHub release;
finish its notes before publishing. Shared-core changes should be included in
the changelogs/releases of every affected tool; a tag identifies a whole,
self-contained monorepo revision.

## History and license

All three original Git histories were imported without rewriting their commits.
The original `ccbox-v1.1.0` tag still points to the original pre-monorepo layout.
See [migration and provenance](docs/migration.md) for exact import commits.

[MIT](LICENSE). Original attribution is preserved in each suite's license.
Box design includes work adapted from [RchGrav/claudebox](https://github.com/RchGrav/claudebox).
This project is independent of the harness vendors and maintainers.
