#!/usr/bin/env bash
# Unit + integration tests for bin/pitools. Sources the command (BASH_SOURCE
# guard keeps main from running) and drives its functions against the real
# tools/ manifests, with an isolated bindir and a fake PATH that supplies every
# tool dep so enable/disable are testable on any host.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export PITOOLS_HOME="$REPO"
export PITOOLS_BIN="$SANDBOX/bin"
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
for dep in pi fzf jq docker sysbox-runc; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done
export PATH="$FAKEBIN:$PATH"

# shellcheck source=/dev/null
source "$REPO/bin/pitools"

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

# current_os: exercise each supported host branch without depending on the
# host that runs this test.
HOST_UNAME="$(uname -s)"
uname() { printf '%s\n' "${PITOOLS_TEST_UNAME:-$HOST_UNAME}"; }
PITOOLS_TEST_UNAME=Linux
assert_eq "$(current_os)" "linux" "current_os identifies Linux"
PITOOLS_TEST_UNAME=Darwin
assert_eq "$(current_os)" "macos" "current_os identifies macOS"
PITOOLS_TEST_UNAME=Plan9
assert_eq "$(current_os)" "unknown" "current_os identifies unsupported platforms"
unset PITOOLS_TEST_UNAME

# The manager must start without PITOOLS_HOME even when readlink lacks GNU -f
# support, as on macOS. The fake rejects only the unsupported option; the
# manager is executed directly so it should not need any other readlink form.
BSD_READLINK_BIN="$SANDBOX/bsd-readlink-bin"
mkdir -p "$BSD_READLINK_BIN"
# shellcheck disable=SC2016
# SC2016: the single-quoted strings are literal contents for the fake executable.
printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "-f" ]; then exit 1; fi' 'exec /usr/bin/readlink "$@"' >"$BSD_READLINK_BIN/readlink"
chmod +x "$BSD_READLINK_BIN/readlink"
startup_out="$(PITOOLS_HOME='' PATH="$BSD_READLINK_BIN:$PATH" bash "$REPO/bin/pitools" version pichat 2>&1)"
startup_rc=$?
assert_eq "$startup_rc" "0" "manager starts without GNU readlink -f"
assert_eq "$startup_out" "pichat 1.0.0" "manager resolves its own prefix portably"

# list_tools includes all three
tools="$(list_tools | sort | tr '\n' ' ')"
assert_eq "$tools" "pibox pichat pisession " "all tools"

# load_manifest sets the contract vars
load_manifest pichat
assert_eq "$NAME" "pichat" "load_manifest: NAME"
assert_eq "$DEPS" "pi" "pichat dependencies"
assert_contains "$PLATFORM" "linux" "load_manifest: PLATFORM"

load_manifest pisession
assert_eq "$DEPS" "fzf jq pi" "pisession dependencies"

# platform_ok: pibox is linux-only, independent of the host that runs this test.
load_manifest pibox
PITOOLS_TEST_UNAME=Linux
assert_eq "$(platform_ok && echo y || echo n)" "y" "platform_ok: pibox supported on linux"
PITOOLS_TEST_UNAME=Darwin
assert_eq "$(platform_ok && echo y || echo n)" "n" "platform_ok: pibox rejected on macOS"
unset PITOOLS_TEST_UNAME
assert_eq "$DEPS" "docker sysbox-runc pi" "pibox dependencies"

# missing_deps: empty when deps present (fake PATH), names the gap when not
load_manifest pisession
assert_eq "$(missing_deps)" "" "missing_deps: none when fzf/jq/pi present"
assert_eq "$(PATH=/nonexistent missing_deps)" "fzf jq pi" "missing_deps: lists all when PATH empty"

# tool_version reads the VERSION file
assert_eq "$(tool_version pichat)" "1.0.0" "pichat version"
assert_eq "$(tool_version pisession)" "1.0.0" "pisession version"
assert_eq "$(tool_version pibox)" "1.0.0" "pibox version"

# enable -> symlink created, tool_enabled true; disable -> removed
enable_tool pichat >/dev/null
assert_eq "$([ -L "$PITOOLS_BIN/pichat" ] && echo y || echo n)" "y" "enable_tool: creates symlink"
assert_eq "$(readlink "$PITOOLS_BIN/pichat")" "$REPO/tools/pichat/pichat" "enable_tool: symlink points at entrypoint"
load_manifest pichat
assert_eq "$(tool_enabled && echo y || echo n)" "y" "tool_enabled: true after enable"
disable_tool pichat >/dev/null
assert_eq "$([ -e "$PITOOLS_BIN/pichat" ] && echo y || echo n)" "n" "disable_tool: removes symlink"

# --force overrides platform constraints as well as missing dependencies.
load_manifest pibox
PITOOLS_TEST_UNAME=Darwin
# shellcheck disable=SC2034 # consumed by enable_tool from the sourced manager
FORCE=1
enable_tool pibox >/dev/null
forced_rc=$?
assert_eq "$forced_rc" "0" "enable_tool: force accepts unsupported platform"
assert_eq "$(readlink "$PITOOLS_BIN/pibox" 2>/dev/null)" "$REPO/tools/pibox/bin/pibox" \
  "enable_tool: force links unsupported tool"
disable_tool pibox >/dev/null
unset PITOOLS_TEST_UNAME

# Uninstall cleanup owns only manager links that point at this prefix. A
# user-managed pitools link must survive, while our manager link is removable.
FOREIGN_PITOOLS="$SANDBOX/foreign-pitools"
printf '#!/usr/bin/env bash\n' >"$FOREIGN_PITOOLS"
ln -s "$FOREIGN_PITOOLS" "$PITOOLS_BIN/pitools"
remove_managed_links >/dev/null
assert_eq "$([ -L "$PITOOLS_BIN/pitools" ] && echo y || echo n)" "y" "uninstall cleanup preserves foreign pitools link"
rm "$PITOOLS_BIN/pitools"
ln -s "$REPO/bin/pitools" "$PITOOLS_BIN/pitools"
remove_managed_links >/dev/null
assert_eq "$([ -e "$PITOOLS_BIN/pitools" ] && echo y || echo n)" "n" "uninstall cleanup removes owned pitools link"

# cmd_list / cmd_version surface the tools
assert_contains "$(cmd_list)" "pichat" "cmd_list: shows pichat"
assert_contains "$(cmd_version pibox)" "pibox 1.0.0" "cmd_version: prints tool + version"

# --- update_prefix: force-push-proof mirror sync (the 'pitools update' git path) ---
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
