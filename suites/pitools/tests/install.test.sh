#!/usr/bin/env bash
# Integration tests for install.sh. Builds a private Git fixture from the
# working tree, then drives the real installer against it with fake external
# dependencies. This catches missing selective links, a missing manager link,
# and non-idempotent updates without needing a network or a remote repository.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
for dep in pi fzf jq; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done
REAL_UNAME="$(command -v uname)"
{
  # shellcheck disable=SC2016 # fake executable needs literal environment references
  printf '%s\n' '#!/usr/bin/env bash' 'if [ -n "${PITOOLS_TEST_UNAME:-}" ]; then' \
    '  printf "%s\\n" "$PITOOLS_TEST_UNAME"' '  exit 0' 'fi'
  printf 'exec %q "$@"\n' "$REAL_UNAME"
} >"$FAKEBIN/uname"
chmod +x "$FAKEBIN/uname"

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

make_source_repo() {
  local source="$SANDBOX/source"
  mkdir -p "$source"
  (cd "$REPO" && tar --exclude=.git --exclude=.superpowers -cf - .) |
    (cd "$source" && tar -xf -)
  git -C "$source" init -q -b main
  git -C "$source" config user.email test@example.invalid
  git -C "$source" config user.name pitools-test
  git -C "$source" add .
  git -C "$source" commit -q -m fixture
  printf '%s' "$source"
}

# Source without invoking main so the installer verifies its helper-loading
# boundary. A removal of load_lib or a wrong tools directory breaks this.
# shellcheck disable=SC2034
# Variables are consumed by the dynamically sourced installer; exporting the
# test-source flag would leak it into the real installer subprocess below.
PITOOLS_HOME="$REPO"
# shellcheck disable=SC2034
PITOOLS_TEST_SOURCE=1
if [ -f "$REPO/install.sh" ]; then
  # shellcheck source=/dev/null
  source "$REPO/install.sh"
  load_lib
  load_manifest pichat
  assert_eq "$DEPS" "pi" "install: load_lib reads pichat manifest"
fi

# A real Git clone avoids depending on a remote or the checked-out branch.
SOURCE_REPO="$(make_source_repo)"
PREFIX="$SANDBOX/prefix"
BIN="$SANDBOX/bin"

# Explicit selections are preflighted before a clone can mutate the prefix.
UNKNOWN_PREFIX="$SANDBOX/unknown-prefix"
unknown_out="$(PITOOLS_REPO="file://$SOURCE_REPO" PITOOLS_HOME="$UNKNOWN_PREFIX" PITOOLS_BIN="$BIN" \
  PITOOLS_BRANCH=main PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=pichat,not-a-tool 2>&1)"
unknown_rc=$?
assert_eq "$unknown_rc" "1" "install: unknown tool selection fails"
assert_eq "$([ -e "$UNKNOWN_PREFIX" ] && echo y || echo n)" "n" "install: validates tools before cloning prefix"
assert_contains "$unknown_out" "unknown tool 'not-a-tool'" "install: identifies unknown tool"
assert_contains "$unknown_out" "Usage:" "install: unknown tool prints guidance"

out="$(PITOOLS_REPO="file://$SOURCE_REPO" PITOOLS_HOME="$PREFIX" PITOOLS_BIN="$BIN" \
  PITOOLS_BRANCH=main PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=pichat,pisession 2>&1)"
assert_eq "$([ -d "$PREFIX/.git" ] && echo y || echo n)" "y" "install: clones prefix"
assert_eq "$(readlink "$BIN/pichat" 2>/dev/null)" "$PREFIX/tools/pichat/pichat" "install: links pichat"
assert_eq "$(readlink "$BIN/pisession" 2>/dev/null)" "$PREFIX/tools/pisession/pisession" "install: links pisession"
assert_eq "$(readlink "$BIN/pitools" 2>/dev/null)" "$PREFIX/bin/pitools" "install: always links pitools"
assert_eq "$([ -e "$BIN/pibox" ] && echo y || echo n)" "n" "install: does not link unselected pibox"
assert_contains "$out" "== pitools install summary ==" "install: prints pitools summary"

# Existing clones update and re-link safely, so a repeated command succeeds.
PITOOLS_REPO="file://$SOURCE_REPO" PITOOLS_HOME="$PREFIX" PITOOLS_BIN="$BIN" \
  PITOOLS_BRANCH=main PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=pichat >/dev/null 2>&1
assert_eq "$?" "0" "install: idempotent re-run succeeds"

# --force overrides both dependency and platform constraints. Simulate macOS
# so the Linux-only pibox manifest is unsupported on every test host.
FORCED_PREFIX="$SANDBOX/forced-prefix"
FORCED_BIN="$SANDBOX/forced-bin"
forced_out="$(PITOOLS_TEST_UNAME=Darwin PITOOLS_REPO="file://$SOURCE_REPO" \
  PITOOLS_HOME="$FORCED_PREFIX" PITOOLS_BIN="$FORCED_BIN" PITOOLS_BRANCH=main \
  PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=pibox --force 2>&1)"
forced_rc=$?
assert_eq "$forced_rc" "0" "install: force accepts unsupported platform"
assert_contains "$forced_out" "pibox" "install: force reports unsupported tool as enabled"
assert_eq "$(readlink "$FORCED_BIN/pibox" 2>/dev/null)" "$FORCED_PREFIX/tools/pibox/bin/pibox" \
  "install: force links unsupported tool"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
