#!/usr/bin/env bash
# Unit + integration tests for bin/cctools. Sources the command (BASH_SOURCE
# guard keeps main from running) and drives its functions against the real
# tools/ manifests, with an isolated bindir and a fake PATH that supplies every
# tool dep so enable/disable are testable on any host.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export CCTOOLS_HOME="$REPO"
export CCTOOLS_BIN="$SANDBOX/bin"
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
for dep in claude fzf jq docker; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done
export PATH="$FAKEBIN:$PATH"

# shellcheck source=/dev/null
source "$REPO/bin/cctools"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
# shellcheck disable=SC2015
# SC2015: ok() always succeeds (PASS+=1 returns 0), so bad() cannot fire spuriously.
assert_eq() { [ "$1" = "$2" ] && ok || bad "$3 (got [$1] want [$2])"; }
assert_contains() { case "$1" in *"$2"*) ok ;; *) bad "$3 ([$1] lacks [$2])" ;; esac }

# current_os
assert_eq "$(current_os)" "linux" "current_os is linux on this host"

# list_tools includes all three
tools="$(list_tools | sort | tr '\n' ' ')"
assert_eq "$tools" "ccbox cchat ccsession " "list_tools enumerates the three tools"

# load_manifest sets the contract vars
load_manifest cchat
assert_eq "$NAME" "cchat" "load_manifest: NAME"
assert_eq "$DEPS" "claude" "load_manifest: DEPS"
assert_contains "$PLATFORM" "linux" "load_manifest: PLATFORM"

# platform_ok: ccbox is linux-only -> ok here; (no macos-only tool to test the negative)
load_manifest ccbox
assert_eq "$(platform_ok && echo y || echo n)" "y" "platform_ok: ccbox supported on linux"
# ccbox needs the sysbox runtime, not just docker — it must be a declared dep
assert_contains "$DEPS" "sysbox-runc" "load_manifest: ccbox DEPS includes sysbox-runc"

# missing_deps: empty when deps present (fake PATH), names the gap when not
load_manifest ccsession
assert_eq "$(missing_deps)" "" "missing_deps: none when fzf/jq/claude present"
assert_eq "$(PATH=/nonexistent missing_deps)" "fzf jq claude" "missing_deps: lists all when PATH empty"

# tool_version reads the VERSION file
assert_eq "$(tool_version cchat)" "1.0.0" "tool_version: cchat"
assert_eq "$(tool_version ccbox)" "1.1.0" "tool_version: ccbox"

# enable -> symlink created, tool_enabled true; disable -> removed
enable_tool cchat >/dev/null
assert_eq "$([ -L "$CCTOOLS_BIN/cchat" ] && echo y || echo n)" "y" "enable_tool: creates symlink"
assert_eq "$(readlink "$CCTOOLS_BIN/cchat")" "$REPO/tools/cchat/cchat" "enable_tool: symlink points at entrypoint"
load_manifest cchat
assert_eq "$(tool_enabled && echo y || echo n)" "y" "tool_enabled: true after enable"
disable_tool cchat >/dev/null
assert_eq "$([ -e "$CCTOOLS_BIN/cchat" ] && echo y || echo n)" "n" "disable_tool: removes symlink"

# cmd_list / cmd_version surface the tools
assert_contains "$(cmd_list)" "cchat" "cmd_list: shows cchat"
assert_contains "$(cmd_version ccbox)" "ccbox 1.1.0" "cmd_version: prints tool + version"

# --- update_prefix: force-push-proof mirror sync (the 'cctools update' git path) ---
# Build a throwaway bare "remote" + a clone of it (our managed mirror), then rewrite the
# remote's history (a force-push) so the clone diverges — a plain 'git pull --ff-only' aborts
# here, but a mirror has no local work to preserve, so update_prefix should reset it.
GEX="$SANDBOX/gitex"
REMOTE="$GEX/remote.git"
SEED="$GEX/seed"
CLONE="$GEX/clone"
mkdir -p "$GEX"
git init -q --bare -b main "$REMOTE"
git init -q -b main "$SEED"
git -C "$SEED" config user.email t@t
git -C "$SEED" config user.name t
printf 'v1\n' >"$SEED/f"
git -C "$SEED" add f
git -C "$SEED" commit -q -m c1
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q -u origin main
git clone -q "$REMOTE" "$CLONE"
# Rewrite the remote's only commit (different content + message) and force-push it.
printf 'v2\n' >"$SEED/f"
git -C "$SEED" add f
git -C "$SEED" commit -q --amend -m c1b
git -C "$SEED" push -q -f origin main
NEW="$(git -C "$SEED" rev-parse HEAD)"
update_prefix "$CLONE" >/dev/null 2>&1
assert_eq "$(git -C "$CLONE" rev-parse HEAD)" "$NEW" "update_prefix: syncs a mirror across a force-push"

# A mirror with uncommitted local edits is left untouched (refuses to discard them).
printf 'local\n' >>"$CLONE/f"
H0="$(git -C "$CLONE" rev-parse HEAD)"
update_prefix "$CLONE" >/dev/null 2>&1
rc=$?
assert_eq "$rc" "1" "update_prefix: refuses when the mirror has local edits"
assert_eq "$(git -C "$CLONE" rev-parse HEAD)" "$H0" "update_prefix: dirty tree leaves HEAD unchanged"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
