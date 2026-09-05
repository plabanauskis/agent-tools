# ccbox redesign — "path-identical mirror" sandbox

**Date:** 2026-06-22
**Status:** Approved design (pre-implementation)
**Supersedes:** the original `ccbox-implementation-plan.md` "Settled Decisions" 5, 6, and the
container-user / workspace-path choices.

---

## 1. Goal & threat model

Run Claude Code on the host machine inside an isolated container whose **only** job is to
protect the **host system** from changes — so the agent can run fully autonomous
(`--dangerously-skip-permissions`) with total freedom and still not be able to damage the
host OS.

The threat model is **one-directional and narrow**:

- **Protect:** the host *system* layer — OS, installed packages, `/usr`, `/etc`, `/var`,
  system services, and anything **outside the explicit mounts** below.
- **Explicitly NOT in scope** (decided by the user):
  - Protecting *other* git repos or the GitHub account from the agent.
  - Restricting the agent's reach to external services / network egress.
  - Kernel-escape protection (the workloads are the user's own repos).
  - Protecting host home contents that are *not* mounted (they aren't reachable).

This reframes the original design, whose accreted decisions (read-write `~/.claude` framed
as a "trust" compromise, per-repo GitHub App token isolation, `/home/dev` + `/workspace`
path remapping) went beyond — and in places *against* — "protect the host."

## 2. Core principle: a path-identical mirror

The container is a **faithful, path-identical mirror** of the user's environment, isolated
**only at the system layer**. Inside, the agent runs as the host user, at the host's real
`$HOME`, with the repo at its **real host path**. Everything Claude writes — memories,
session history, plugins, config, refreshed credentials — therefore lands exactly where the
host expects it. The container differs from the host in one way only: the system layer is
the image's own and ephemeral.

This principle eliminates every path-translation hack that the old design needed (see §5),
because there is no path translation: host and box paths are identical.

### Why path-identity matters (root cause of the old bugs)

Claude keys project-scoped state — **memories, session history, "trust this folder"** — by
the working-directory path. The old box ran the repo at `/workspace`, so everything the
agent wrote landed in a `-workspace` project bucket, **separate** from the repo's real
bucket (`-home-<user>-...-<repo>`). The desired memory-persistence was silently broken.
Plugins broke for the same reason: their cache/marketplace locations are recorded as
absolute paths under the host home (`/home/<user>/.claude/plugins/...`), which did not exist
at the box's `/home/dev`. Running at identical paths fixes both at the source.

## 3. Architecture & launch flow

`ccbox` (host launcher), run from inside a git repo:

1. `git rev-parse --show-toplevel` → repo root (abort if not a git repo).
2. Confirm the `sysbox-runc` runtime is available (else point to the prerequisite).
3. Resolve the host `claude` binary: `readlink -f "$(command -v claude)"`. Abort with a
   clear message if `claude` is not found on the host.
4. Compute a per-project slug → inner-Docker data volume `ccbox-docker-<slug>`.
5. Build the published-port list (default range + `$CCBOX_PORTS` + `<repo>/.ccbox/ports`).
6. `docker run -it --rm --runtime=sysbox-runc` as the host UID/GID, `$HOME` = real host
   home, with the mounts/env in §4, running the **host** `claude` binary.
7. `entrypoint.sh` starts the inner `dockerd` (sysbox makes it host-safe), then `exec`s the
   resolved host `claude --dangerously-skip-permissions "$@"`.

## 4. Mounts & settings (the complete contract)

Container runs as the **host user** (real username, UID/GID), `$HOME` = the host home path.

| Mount / setting | Mode | Why |
|---|---|---|
| repo at its **real host path** (= workdir) | read-write | edits + commits are real; unifies memories/history/trust |
| `~/.claude` at real path | **read-write** | memories, config, plugins, and credential-refresh persist to host (the stated goal) |
| `~/.gitconfig` at real path | read-only | commit identity + settings; git only reads it to author commits |
| host `claude` install (`~/.local/share/claude`) | read-only | box runs the **host's** binary → always matches host version; agent cannot overwrite it; in-box self-update stays disabled |
| `ccbox-docker-<slug>` → `/var/lib/docker` | volume | inner Docker data (DBs, image cache) persists per project |
| `-e CLAUDE_CONFIG_DIR=$HOME/.claude` | — | keeps `.claude.json` inside the mounted dir → no re-onboarding, avoids the single-file-mount `EBUSY` problem |
| `-e HOME=$HOME`, real username/UID/GID | — | path-identity; non-root (Claude refuses bypass mode as root) |
| published ports (`-p`) | — | host browser → in-box app |
| terminal tint + `-e CCBOX=1` / `CCBOX_VERSION` | — | sandbox visual cue + detectable marker |
| inner `dockerd` (started by entrypoint) | — | run the repo's own `docker compose` stack |

**Not mounted (by decision):** `~/.config/gh` and any GitHub credentials (no push/PR from
the box — commits are local, the user pushes from the host); `~/.ssh` (no SSH needed — the
user's GitHub auth is HTTPS-via-`gh`, and the user does not sign commits); shell dotfiles
(`~/.bashrc`/`~/.profile`/version-manager shims) — the box uses the image's default shell
with baked-in toolchains on `PATH`.

### Claude binary: mounted from host, not built in

The image does **not** install `claude`. The launcher resolves the host's current `claude`
and mounts its install tree read-only; the box executes that binary. Consequences:

- The box's `claude` version **always equals the host's**, automatically, with no rebuild.
- Deletes the in-image `npm install`, the `CLAUDE_VERSION` build arg, and any
  build-time version-resolution logic.
- **Assumption:** host uses the **native installer** layout (a single self-contained ELF
  under `~/.local/share/claude/versions/`). A host that installed `claude` via npm-global
  would instead need its `node_modules` tree mounted; the launcher detects the resolved path
  generically and errors clearly if `claude` is absent.
- Node.js stays in the image (language toolchain + npx-based plugins like context7), just
  not for `claude` itself.

## 5. What gets deleted

- **The entire GitHub App subsystem:** `bin/ccbox-token`, `bin/ccbox-setup`, the `.pem` /
  `app.env` files, the RS256 JWT minting, and all GitHub-App documentation. It only ever
  protected *other repos* — out of scope. Nothing replaces it (no GitHub access in-box).
- **All path-translation hacks:** the `/home/dev` user, the `/workspace` remap, the plugin
  path-bridge symlink (`CCBOX_HOST_HOME` + the entrypoint `ln -s`), and the first-run
  `.claude.json` seed. Unnecessary once paths mirror the host.
- **The in-image `claude` install** and its versioning machinery (see §4).

## 6. What's kept

- **Inner Docker + sysbox + per-project data volume** — the user needs to run the repo's own
  stack; sysbox also provides the user-namespace remap that hardens the host boundary.
- **Published ports**, the **terminal tint** sandbox cue, the **`CCBOX=1`** marker, and the
  cross-project language caches.
- **The Dockerfile layer reorder** (entrypoint `COPY` after the heavy toolchain layers) so
  rebuilds stay cheap. Minor, but harmless and useful.

## 7. Security model

- **Protected:** the host system (OS, packages, `/usr`, `/etc`, `/var`, anything outside the
  explicit mounts). Enforced by: ephemeral image rootfs + non-root container user + sysbox
  user-namespace remap (container-root ≠ host-root) + the documented HARD RULES (never mount
  the host Docker socket, never `--privileged`, never `--network=host`).
- **In-scope blast radius (agent can affect, by design):** the mounted repo (git history is
  the undo), `~/.claude` (memories/config/plugins/credentials), and the project's
  inner-Docker data volume. **Nothing else** — no other repos, no GitHub account (no creds
  present), no other home contents (not mounted).
- **Accepted caveats** (inherent to the goals, named explicitly):
  - Read-write `~/.claude` means the agent *could* corrupt the host's Claude state. This is
    the price of memory-persistence and is accepted.
  - The box may surface the account's claude.ai connectors (Gmail/Drive/Calendar) via the
    shared login; they are auth-gated and are not a *host* risk, so out of scope.

## 8. Breaking changes & migration

- One-time image rebuild (new user/home; no in-image `claude`).
- `~/.config/ccbox` (GitHub App key + `app.env`) becomes dead; `uninstall`/docs should
  mention removing it. Optionally delete the GitHub App itself in GitHub settings.
- The orphaned `-workspace` project bucket can be deleted; real-path buckets take over.
- `CCBOX_VERSION` bump; `README.md` and `CLAUDE.md` rewritten to the new model.
- **Working-tree note:** the current branch has experimental edits from the abandoned
  "share + bridge" direction (`entrypoint.sh` symlink bridge, `CCBOX_HOST_HOME` in
  `bin/ccbox`, `Dockerfile` claude-version arg, a now-incorrect `README.md` bullet). These
  are to be reverted/rewritten during implementation, not carried forward.

## 9. Non-goals (unchanged from original where still valid)

- No network egress firewall / allowlist.
- Linux host only; amd64 (native-installer `claude` is amd64 here).
- No microVM/Kata/KVM.
- No headless/`-p` print mode — interactive chat only.

## 10. Open items / future

- Generic host-`claude` path detection for npm-global installs (currently native-installer
  layout assumed; error clearly otherwise).
- Optional shell-dotfile mirroring (deferred — image defaults for now).

## Appendix A — Empirical verification (already done)

These were tested against the real `ccbox:latest` image during design, not assumed:

- **Plugins fail in the old box:** all 14 report `failed to load — marketplace … cache-miss`
  because recorded paths are `/home/<user>/.claude/...` and the box home is `/home/dev`.
- **Path-identity fixes them:** bridging the host home path made all 14 load (`✔ enabled`),
  proving the root cause is the path mismatch.
- **Memory fragmentation is real:** `~/.claude/projects/` contains both
  `-home-paulius-source-github-plabanauskis-ccbox` (host) and `-workspace` (box) buckets.
- **Host `claude` runs in the box:** mounting `~/.local` RO and running `claude --version`
  inside `ccbox:latest` printed `2.1.185` — the host's exact version (box glibc 2.36 suffices
  for the self-contained ELF).
- **Commit-as-user works with RO gitconfig:** in-box `git var GIT_AUTHOR_IDENT` →
  `Paulius Labanauskis <paulius@labanausk.is>`; repo `.git/` writable; `~/.gitconfig` not
  writable. Identity is read-only-safe; commits land in the RW repo.
