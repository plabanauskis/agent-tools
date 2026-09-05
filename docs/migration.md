# Migration and provenance

## What has and has not moved

Development is consolidated in `plabanauskis/agent-tools`. The original
`cctools`, `cotools`, and `pitools` repositories and source checkouts are left
unchanged. They are not archived, redirected, or automatically updated by this
migration. Existing installed clones still track their original repositories
until you explicitly replace them.

The new repository is private. Authenticate Git before installation or updating;
unauthenticated raw GitHub installer URLs are not a supported private install
method. See the [root installation guide](../README.md#install-while-this-repository-is-private).

## Migrate one installed suite

These steps concern the **installed clone** (normally `~/.local/share/<suite>`),
not your source checkout. Do not run box uninstall just to migrate: it can remove
images or volumes that you want to retain.

Example for Pi; substitute the suite names and overrides for Claude or Codex:

1. Record your installation settings and enabled tools:

   ```bash
   pitools list
   printf 'prefix: %s\nbin: %s\n' "${PITOOLS_HOME:-$HOME/.local/share/pitools}" "${PITOOLS_BIN:-$HOME/.local/bin}"
   ```

   Save the list of enabled tools. Inspect any local edits in the installed clone
   and keep them in your backup. Also note custom `PITOOLS_REPO`/`PITOOLS_BRANCH`
   settings; an old repository override must not be reused accidentally.

2. Authenticate and obtain the new source checkout:

   ```bash
   gh auth login
   gh auth setup-git
   gh repo clone plabanauskis/agent-tools
   cd agent-tools
   ```

   If you already have this checkout, use it rather than cloning again.

3. Move the old installed clone aside, without deleting it:

   ```bash
   prefix="${PITOOLS_HOME:-$HOME/.local/share/pitools}"
   backup="${prefix}.pre-agent-tools"
   test -d "$prefix/.git" && test ! -e "$backup" && mv -- "$prefix" "$backup"
   ```

   Stop if the move did not succeed. Existing command symlinks may be temporarily
   dangling until the installation completes. The backup preserves the old clone
   and its Git configuration, not a copy of harness state.

4. Install **all previously enabled tools**, using the new upstream explicitly:

   ```bash
   # Example: only these two were previously enabled; use your saved selection.
   PITOOLS_REPO=https://github.com/plabanauskis/agent-tools.git PITOOLS_BRANCH=main \
     bash install.sh --suite=pitools --tools=pichat,pisession
   ```

   Keep custom `PITOOLS_HOME` and `PITOOLS_BIN` exported if you use them. Add
   `pibox` to the selection if it was enabled. If dependencies are temporarily
   unavailable, `--force` preserves the requested links but does not install the
   missing dependencies. Check the printed enabled/skipped summary.

5. Verify before removing any backup:

   ```bash
   pitools list
   pitools doctor
   pitools version
   readlink "${PITOOLS_BIN:-$HOME/.local/bin}/pichat"
   ```

   Tool links now point under `<prefix>/suites/pitools/tools/`; the manager link
   points to `<prefix>/bin/pitools`. If you deliberately dropped a formerly
   enabled tool, inspect and remove only its stale old `<prefix>/tools/...`
   symlink, not an unrelated user-managed command.

Repeat separately for `cctools` and `cotools`. Never assign two suites the same
prefix: the ownership marker makes the installer and manager reject that mix.

### State and rollback

Session/state directories, credentials, `.ccbox`/`.cobox`/`.pibox` project
settings, image names, and Docker volume names are unchanged. Migrating does not
require a Docker rebuild. The shared Codex/Pi recipe affects the next explicit
image build only.

To roll back, keep both clones: move the new installed prefix to a distinct
backup location, restore the old clone to its original prefix, and restore
owned command symlinks to the original layout using the old manager's `enable`
commands. Restore the manager symlink to `<prefix>/bin/<suite>` as well. Do not
run the new manager's uninstall after restoring the old clone; it is intentionally
not marked as installer-managed agent-tools state.

## Source history

The import commits use merge ancestry plus prefixed trees. Original commit IDs
remain reachable from `main`; no original repository was rewritten.

| Source | Imported source HEAD | Import merge |
| --- | --- | --- |
| cctools | `84c9773b9935d7f40cc61a7ac8b8e9c389012761` | `b62f14c` |
| cotools | `f64adc500e2e7ab042b6e0579fe0ef3041737925` | `d738e86` |
| pitools | `f2f32b810222b4324d0a48d6e6ad36b4bb6bd76e` | `c98e38c` |

The retained `ccbox-v1.1.0` tag points to its original commit and original
single-suite layout, not the new monorepo. New per-tool tags identify complete
monorepo snapshots. For pre-import history, inspect the original commit directly
with `git show <source-commit>:<original-path>`; file paths before the import do
not have the `suites/<suite>/` prefix.

The licenses and original tool changelogs remain under each suite. Root shared
code uses the same MIT license. Original histories can contain older code and
documentation; audit the full reachable history before making this repository
public, not only the current tree.
