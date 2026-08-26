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
for dep in codex fzf jq; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done

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
  git -C "$source" config user.name cotools-test
  git -C "$source" add .
  git -C "$source" commit -q -m fixture
  printf '%s' "$source"
}

# Source without invoking main so the installer verifies its helper-loading
# boundary. A removal of load_lib or a wrong tools directory breaks this.
# shellcheck disable=SC2034
# Variables are consumed by the dynamically sourced installer; exporting the
# test-source flag would leak it into the real installer subprocess below.
COTOOLS_HOME="$REPO"
# shellcheck disable=SC2034
COTOOLS_TEST_SOURCE=1
if [ -f "$REPO/install.sh" ]; then
  # shellcheck source=/dev/null
  source "$REPO/install.sh"
  load_lib
  load_manifest cochat
  assert_eq "$DEPS" "codex" "install: load_lib reads cochat manifest"
fi

# A real Git clone avoids depending on a remote or the checked-out branch.
SOURCE_REPO="$(make_source_repo)"
PREFIX="$SANDBOX/prefix"
BIN="$SANDBOX/bin"
out="$(COTOOLS_REPO="file://$SOURCE_REPO" COTOOLS_HOME="$PREFIX" COTOOLS_BIN="$BIN" \
  COTOOLS_BRANCH=main PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=cochat,cosession 2>&1)"
assert_eq "$([ -d "$PREFIX/.git" ] && echo y || echo n)" "y" "install: clones prefix"
assert_eq "$(readlink "$BIN/cochat" 2>/dev/null)" "$PREFIX/tools/cochat/cochat" "install: links cochat"
assert_eq "$(readlink "$BIN/cosession" 2>/dev/null)" "$PREFIX/tools/cosession/cosession" "install: links cosession"
assert_eq "$(readlink "$BIN/cotools" 2>/dev/null)" "$PREFIX/bin/cotools" "install: always links cotools"
assert_eq "$([ -e "$BIN/cobox" ] && echo y || echo n)" "n" "install: does not link unselected cobox"
assert_contains "$out" "== cotools install summary ==" "install: prints cotools summary"

# Existing clones update and re-link safely, so a repeated command succeeds.
COTOOLS_REPO="file://$SOURCE_REPO" COTOOLS_HOME="$PREFIX" COTOOLS_BIN="$BIN" \
  COTOOLS_BRANCH=main PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=cochat >/dev/null 2>&1
assert_eq "$?" "0" "install: idempotent re-run succeeds"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
