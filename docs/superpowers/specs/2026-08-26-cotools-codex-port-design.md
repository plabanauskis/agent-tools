# cotools Codex Port Design

**Date:** 2026-08-26  
**Status:** Approved for implementation  
**Parity baseline:** `cctools` commit `84c9773` (`ccbox-v1.1.0`)

## Goal

Build `cotools` as an independent, Codex-native logical port of
`/home/paulius/source/github/plabanauskis/cctools`. Preserve the source
suite's user experience, lifecycle behavior, isolation model, documentation
quality, and test coverage while replacing Claude Code assumptions with Codex
CLI behavior.

The user-facing tools are:

- `cochat`: open Codex in a new throwaway directory.
- `cosession`: find and resume local Codex CLI or Desktop sessions with `fzf`.
- `cobox`: run Codex autonomously inside the existing Docker + sysbox isolation
  model.

The bundle also provides `cotools`, a lifecycle-only manager equivalent to
`cctools`.

## Product Decisions

### Distribution model

`cotools` is a standalone repository, not a wrapper around or runtime
dependency on `cctools`. Its directory structure deliberately mirrors the
source so behavior can be compared directly and future fixes can be ported
without a generator.

### Naming

All public Claude-oriented names become Codex-oriented names:

| Source | Port |
|---|---|
| `cctools` | `cotools` |
| `cchat` | `cochat` |
| `ccsession` | `cosession` |
| `ccbox` | `cobox` |
| `CCTOOLS_*` | `COTOOLS_*` |
| `CCBOX_*` | `COBOX_*` |
| `.ccbox/ports` | `.cobox/ports` |
| `ccbox-*` Docker resources | `cobox-*` Docker resources |

The new suite starts at version `1.0.0` for all three tools. The changelogs
describe the Codex port as the initial release rather than copying the source
project's release history.

### Visual identity

The approved direction is **Node Trail**:

- Retain the source family's chat bubble, session rows, and isometric box
  silhouettes.
- Replace Claude orange with Codex green (`#10A37F`).
- Use three-point activity cues within each icon.
- Highlight the `co` prefix in wordmarks.
- Provide light and dark icon/wordmark SVGs plus social preview SVG and rendered
  PNG for each tool.
- Do not embed, imitate, recolor, or modify the official OpenAI Blossom. The
  suite remains independently branded and does not imply OpenAI endorsement.

## Repository Structure

The port keeps the source layout:

```text
cotools/
├── .githooks/pre-push
├── .gitignore
├── LICENSE
├── README.md
├── install.sh
├── bin/cotools
├── lib/cotools-common.sh
├── scripts/check.sh
├── scripts/dev-setup.sh
├── scripts/release.sh
├── tests/
│   ├── cotools.test.sh
│   ├── install.test.sh
│   └── release.test.sh
└── tools/
    ├── cochat/
    ├── cosession/
    └── cobox/
```

Each tool directory contains `tool.manifest`, `VERSION`, `CHANGELOG.md`, a
README, assets, an executable, and its own tests. `cobox` additionally contains
the Dockerfile, entrypoint, and gated smoke test.

## Bundle Lifecycle

### Installer

`install.sh` retains the source behavior with these defaults:

- Repository: `https://github.com/plabanauskis/cotools.git`
- Prefix: `${COTOOLS_HOME:-$HOME/.local/share/cotools}`
- Binary directory: `${COTOOLS_BIN:-$HOME/.local/bin}`
- Branch: `${COTOOLS_BRANCH:-main}`

It supports `--all`, `--tools=cochat,cosession,cobox`, `--force`, interactive
selection, and noninteractive auto-selection. It always installs the `cotools`
manager symlink and only enables requested tools whose platform and dependency
contracts pass unless forced.

### Manager

`cotools` supports the same lifecycle commands as `cctools`:

```text
cotools list
cotools doctor [tool]
cotools enable <tool> [--force]
cotools disable <tool>
cotools update
cotools uninstall
cotools version [tool]
cotools help
```

Manifests remain the source of truth for entry points, commands, dependencies,
platforms, descriptions, and post-enable guidance. Updates fetch the configured
upstream and hard-reset the managed mirror to it only when tracked files are
clean; uncommitted tracked edits cause a refusal, and untracked files survive.

The manager never removes Docker images or volumes. It reminds users to run
`cobox uninstall` first when matching runtime resources remain.

## cochat

`cochat` is a strict Bash script with one behavior:

1. Create a fresh directory matching
   `${TMPDIR:-/tmp}/cochat.XXXXXX` with `mktemp -d`.
2. Change into it inside the script process.
3. Replace the script process with `codex`, passing all arguments unchanged.

`cochat --help` prints its own help without launching Codex. The temp directory
is intentionally retained so its session can be resumed until ordinary temp
cleanup removes it.

Manifest contract:

- Dependencies: `codex`
- Platforms: Linux and macOS
- Entrypoint/command: `cochat`

## cosession

### Session scope

`cosession` discovers rollout files recursively under:

```text
${CODEX_HOME:-$HOME/.codex}/sessions/**/rollout-*.jsonl
```

It includes root user sessions from Codex CLI and Codex Desktop. A rollout is a
root user session when its first `session_meta.payload.source` value is a JSON
string. Internal child, guardian, and other agent rollouts use structured
`source` objects and are excluded.

Archived sessions under `archived_sessions` are not listed. Noninteractive
sessions are not specially excluded when they exist in the active sessions
tree; an explicit session UUID remains resumable by Codex.

### Metadata extraction

For each included rollout, `cosession` reads:

- `id`: `session_meta.payload.id`, falling back to
  `session_meta.payload.session_id`.
- `cwd`: `session_meta.payload.cwd`.
- `branch`: `session_meta.payload.git.branch`, or empty when absent.
- `active`: rollout file modification time.
- `source`: the string `session_meta.payload.source` value.

The summary uses the first nonempty value in this precedence order:

1. The latest matching `thread_name` for the session UUID in
   `$CODEX_HOME/session_index.jsonl`.
2. The first matching nonempty `text` in `$CODEX_HOME/history.jsonl`.
3. The first nonempty `input_text.text` from a user `response_item` in the
   rollout, ignoring injected `<environment_context>...</environment_context>`
   records.
4. The session UUID.

Summaries are reduced to one line by stripping control separators, collapsing
whitespace, and trimming. A malformed rollout lacking a valid UUID or working
directory is skipped instead of producing an unusable picker row.

### Picker

The `fzf` interface preserves `ccsession`'s layout and behavior:

- Newest-active sessions first.
- Live/gone glyph, relative time, shortened directory, branch, and summary.
- Character-aware padding and truncation.
- Right-side preview with status, directory, branch, source, active time, UUID,
  and summary.
- ESC or no selection is a clean cancellation.

Selecting a live session changes into its recorded directory and executes:

```bash
codex resume <session-uuid>
```

Selecting a session whose directory is gone prints a clear error and exits
nonzero. `--help` does not inspect state or launch `fzf`.

Manifest contract:

- Dependencies: `fzf jq codex`
- Platforms: Linux and macOS
- Entrypoint/command: `cosession`

The implementation continues to rely on GNU `find`, `grep`, `date`, and `stat`,
matching the source tool's effective runtime contract.

## cobox

### Security model

`cobox` keeps the source threat model: protect the host system layer while
granting the agent full autonomy over explicitly mounted project and Codex
state. It uses Docker with `--runtime=sysbox-runc`, never mounts the host Docker
socket, never uses `--privileged`, and does not use host networking.

Codex launches with:

```text
--dangerously-bypass-approvals-and-sandbox
```

This is appropriate because the sysbox container is the external sandbox. The
repository mount and Codex state mount are intentionally writable and remain
inside the documented blast radius.

### Host integration

At launch, `cobox` resolves the real host `codex` executable.

- For the official npm layout ending in `@openai/codex/bin/codex.js`, mount the
  entire detected `@openai/codex` package directory read-only at the identical
  path. This includes its nested platform package and native executable.
- For a directly executable native Codex binary, mount that file read-only at
  its identical path.
- An executable script outside the supported official npm layout fails with an
  actionable error rather than mounting an incomplete installation.

The image includes Node.js, so the mounted npm launcher uses the container's
Node runtime while loading the exact host package version.

State comes from `${CODEX_HOME:-$HOME/.codex}` and is mounted read-write at the
identical path. `CODEX_HOME` is exported inside the container. This preserves
authentication, config, skills, plugins, session history, and credential
refresh. The project is mounted read-write at its real host path and becomes
the container working directory. `~/.gitconfig` is mounted read-only when
present.

`OPENAI_API_KEY` and `CODEX_ACCESS_TOKEN` are passed through only when already
set. No SSH or GitHub credentials are mounted, so the agent can make local
commits but cannot gain push credentials from `cobox`.

### Commands and runtime behavior

`cobox` retains the source dispatch model:

```text
cobox [codex args...]
cobox build
cobox doctor
cobox uninstall
cobox help
cobox version
```

The first reserved word invokes a `cobox` subcommand; all other arguments pass
unchanged to Codex after the required bypass flag.

- Launching within a Git repository mounts the repository root.
- Launching outside Git warns that edits have no Git undo and requires an
  explicit TTY confirmation. Unattended launch defaults to abort.
- A missing image offers an interactive build and otherwise fails with the
  exact build command.
- `cobox doctor` checks Docker, sysbox, the host Codex executable, supported
  install layout, `codex login status`, Codex state, and the image.
- `cobox uninstall` removes the image and shared caches, then separately asks
  before deleting per-project inner-Docker data volumes.

Path-identical mounts, persistent language caches, per-project inner-Docker
data, terminal tinting, the `COBOX=1` marker, configurable ports, and the
`COBOX_NO_DOCKER=1` fast path remain unchanged in behavior. Default published
ports are `3000-3010`; extra ports come from `COBOX_PORTS` and
`<repo>/.cobox/ports`.

Docker resources use these names:

- Image: `${COBOX_IMAGE:-cobox:latest}`
- Caches: `cobox-npm`, `cobox-cargo`, `cobox-go`, `cobox-uv`, `cobox-nuget`
- Project data: `cobox-docker-<sanitized-project-name>`

Manifest contract:

- Dependencies: `docker sysbox-runc codex`
- Platform: Linux
- Entrypoint/command: `bin/cobox` / `cobox`

### Container image

The Dockerfile remains Debian Bookworm based and retains the source toolchain:

- Node.js 24
- Python 3 and `uv`
- Go 1.26.x
- Rust stable
- .NET 10
- Git, GitHub CLI, jq, ripgrep, fd, OpenSSL, socat
- Inner Docker Engine and Compose v2

The image mirrors host username, UID, GID, and home path. Codex itself is not
installed in the image; the host installation is mounted at runtime to prevent
version skew.

## Error Handling

The port preserves source exit semantics and adds Codex-specific validation:

- Unknown installer arguments, lifecycle commands, tools, and invalid semantic
  versions fail nonzero with usage guidance.
- Missing dependencies and unsupported platforms prevent enabling unless the
  manager's existing `--force` contract applies.
- Empty session stores, malformed rollouts, missing working directories, and
  failed directory changes produce specific errors without launching Codex.
- `cobox` stops before Docker launch when sysbox, host Codex, supported host
  installation, Codex state/login, or image requirements fail.
- Destructive uninstall actions remain explicitly confirmed and default to no
  without a controlling terminal.

## Testing Strategy

Implementation follows red-green-refactor cycles. Ported tests are written and
observed failing against the empty target before production scripts are added.

### Bundle tests

- Manifest enumeration and contract values for all three tools.
- Enable/disable symlink behavior and versions.
- Force-push-resilient mirror updates and refusal on local tracked edits.
- Installer selection, cloning, linking, and idempotent reruns using a temporary
  Git fixture so tests do not depend on the target checkout already being a Git
  repository.
- Release version/changelog helpers, including the embedded `COBOX_VERSION`.

### Tool tests

- `cochat`: fresh directory, unchanged arguments, and help short-circuit using a
  fake `codex` recorder.
- `cosession`: time/directory formatting, CLI and Desktop rollout parsing,
  structured subagent-source exclusion, summary precedence, environment-context
  skipping, malformed-rollout skipping, live/gone rows, preview content, empty
  store behavior, and resume invocation.
- `cobox`: symlink-safe Dockerfile discovery, non-Git launch confirmation,
  npm-package and native-binary detection, unsupported launcher rejection,
  Codex state/package/project mounts, bypass flag ordering, API environment
  passthrough, and renamed Docker resources using fake executables.

### Repository checks

`scripts/check.sh` runs:

1. `bash -n` for every owned shell script.
2. `shellcheck -x` when installed.
3. `shfmt -i 2 -ci -d` when installed.
4. Every root and per-tool Bash test suite.
5. The `cobox` toolchain/inner-Docker smoke test only when sysbox and the image
   are available; otherwise it reports a visible skip.

## Documentation

The root README and per-tool READMEs retain the source project's structure but
describe Codex commands, state, authentication, environment variables, security
boundaries, and troubleshooting accurately. Source repository links become
`plabanauskis/cotools`. The MIT license and the existing attribution for the
box design remain.

The root security section links directly to `cobox`'s documented threat model.
Documentation explicitly states that `cotools` is an independent utility suite
for Codex and is not affiliated with or endorsed by OpenAI.

## Out of Scope

- Sharing runtime code with `cctools`.
- Migrating Claude Code sessions into Codex.
- Listing archived Codex sessions.
- Listing or resuming internal subagent/guardian sessions.
- Supporting Windows for `cochat` or `cosession`.
- Supporting non-sysbox container runtimes for `cobox`.
- Mounting host SSH, GitHub, or Docker credentials into `cobox`.
- Embedding the official OpenAI logo in `cotools` branding.

## Acceptance Criteria

The port is complete when:

1. `cotools list`, `doctor`, `enable`, `disable`, `update`, `uninstall`, and
   `version` match the source lifecycle behavior under the new names.
2. `cochat` launches the installed Codex CLI from a unique temp directory with
   unchanged arguments.
3. `cosession` shows root CLI and Desktop sessions, excludes internal agent
   sessions, and resumes a selected live session by UUID from its original
   directory.
4. `cobox` launches the exact host Codex version inside sysbox with path-identical
   project/state access and Codex approval/sandbox bypass enabled.
5. All documentation and source text use Codex/cotools naming except explicit
   historical attribution or comparison context.
6. Node Trail SVG/PNG assets render correctly in both light and dark contexts.
7. `scripts/check.sh` completes with all applicable checks passing and only
   environment-gated checks skipped with an explicit reason.

