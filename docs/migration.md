# Migration and provenance

## What has and has not moved

Development is consolidated in `plabanauskis/harness-tools`. The original
`cctools`, `cotools`, and `pitools` repositories and source checkouts are left
unchanged. They are not archived, redirected, or automatically updated by this
migration. Existing installed clones still track their original repositories
until you explicitly replace them.

The repository is public. Installation and updates need no GitHub account.
See the [root installation guide](../README.md#install) for the standalone
`curl | bash` installer and read-before-running option.

Already installed from this monorepo, formerly named **agent-tools**? No
reinstall is needed; see the rename guidance below. The separate-repository
migration procedure applies only to clones of the original three repositories.

## Repository rename

The GitHub repository was renamed from `plabanauskis/agent-tools` to
`plabanauskis/harness-tools`; it was not recreated. Commit IDs, tags, issues,
releases, and public visibility are preserved. The separate `agentic-tools`
repository is unrelated and unchanged.

GitHub redirects old repository Git URLs, but explicitly updating each clone's
origin avoids depending on that redirect. For example, for a Pi installation:

```bash
prefix="${PITOOLS_HOME:-$HOME/.local/share/pitools}"
git -C "$prefix" remote get-url origin   # inspect before changing a fork/mirror
git -C "$prefix" remote set-url origin https://github.com/plabanauskis/harness-tools.git
```

Apply the equivalent change to other suite clones only if their origin was the
old monorepo, not an intentional fork or one of the original suite repositories.
Update exported `*_REPO` overrides and any saved installer commands too.

For a development checkout, rename its local directory if desired and update
its Git origin to the new URL. If an installed clone uses a `file://` origin
pointing to that checkout, update it to the checkout's new absolute path;
GitHub redirects cannot repair local filesystem URLs. Likewise, manually linked
commands pointing directly into a moved development checkout need new targets.

Keep suite prefixes, command names, environment overrides, Docker image/volume
names, and the `.agent-tools-suite` ownership marker unchanged. That marker
intentionally retains its old name so existing installations still pass the
update/uninstall ownership checks. No Docker rebuild or state migration is needed.

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

2. Obtain the new source checkout (no authentication required):

   ```bash
   git clone https://github.com/plabanauskis/harness-tools.git
   cd harness-tools
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
   PITOOLS_REPO=https://github.com/plabanauskis/harness-tools.git PITOOLS_BRANCH=main \
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
not marked as installer-managed monorepo state.

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
documentation. The initial public release was checked with Gitleaks against
both the reachable Git history and current tracked files, with no leaks found.
Repeat both checks before publishing future imported histories; a clean scan
is not a guarantee that every sensitive value has been identified.
