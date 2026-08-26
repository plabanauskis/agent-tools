#!/usr/bin/env bash
# Unit + integration tests for bin/cotools. Sources the command (BASH_SOURCE
# guard keeps main from running) and drives its functions against the real
# tools/ manifests, with an isolated bindir and a fake PATH that supplies every
# tool dep so enable/disable are testable on any host.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export COTOOLS_HOME="$REPO"
export COTOOLS_BIN="$SANDBOX/bin"
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
for dep in codex fzf jq docker sysbox-runc; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done
export PATH="$FAKEBIN:$PATH"

# shellcheck source=/dev/null
source "$REPO/bin/cotools"

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
assert_eq "$tools" "cobox cochat cosession " "all tools"

# load_manifest sets the contract vars
load_manifest cochat
assert_eq "$NAME" "cochat" "load_manifest: NAME"
assert_eq "$DEPS" "codex" "cochat dependencies"
assert_contains "$PLATFORM" "linux" "load_manifest: PLATFORM"

load_manifest cosession
assert_eq "$DEPS" "fzf jq codex" "cosession dependencies"

# platform_ok: cobox is linux-only -> ok here; (no macos-only tool to test the negative)
load_manifest cobox
assert_eq "$(platform_ok && echo y || echo n)" "y" "platform_ok: cobox supported on linux"
assert_eq "$DEPS" "docker sysbox-runc codex" "cobox dependencies"

# missing_deps: empty when deps present (fake PATH), names the gap when not
load_manifest cosession
assert_eq "$(missing_deps)" "" "missing_deps: none when fzf/jq/codex present"
assert_eq "$(PATH=/nonexistent missing_deps)" "fzf jq codex" "missing_deps: lists all when PATH empty"

# tool_version reads the VERSION file
assert_eq "$(tool_version cochat)" "1.0.0" "cochat version"
assert_eq "$(tool_version cosession)" "1.0.0" "cosession version"
assert_eq "$(tool_version cobox)" "1.0.0" "cobox version"

# enable -> symlink created, tool_enabled true; disable -> removed
enable_tool cochat >/dev/null
assert_eq "$([ -L "$COTOOLS_BIN/cochat" ] && echo y || echo n)" "y" "enable_tool: creates symlink"
assert_eq "$(readlink "$COTOOLS_BIN/cochat")" "$REPO/tools/cochat/cochat" "enable_tool: symlink points at entrypoint"
load_manifest cochat
assert_eq "$(tool_enabled && echo y || echo n)" "y" "tool_enabled: true after enable"
disable_tool cochat >/dev/null
assert_eq "$([ -e "$COTOOLS_BIN/cochat" ] && echo y || echo n)" "n" "disable_tool: removes symlink"

# cmd_list / cmd_version surface the tools
assert_contains "$(cmd_list)" "cochat" "cmd_list: shows cochat"
assert_contains "$(cmd_version cobox)" "cobox 1.0.0" "cmd_version: prints tool + version"

# --- update_prefix: force-push-proof mirror sync (the 'cotools update' git path) ---
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
