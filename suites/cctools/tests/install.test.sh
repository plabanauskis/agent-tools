#!/usr/bin/env bash
# Tests for install.sh: unit-test its helpers (sourced) and run one full
# non-interactive install against a file:// clone of THIS repo into a sandbox
# prefix + bindir, with a fake PATH supplying tool deps.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
for dep in claude fzf jq docker; do
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
assert_eq() {
  if [ "$1" = "$2" ]; then
    ok
  else
    bad "$3 (got [$1] want [$2])"
  fi
}

# --- unit: source install.sh without running main, then load the shared lib
# (load_lib sets CCTOOLS_TOOLS_DIR=$CCTOOLS_HOME/tools and sources the helpers) ---
# Note: VAR=val prefix to a bash builtin (source) is temporary — the shell restores
# the previous variable state after the builtin returns (bash 5.x behaviour). Set
# variables explicitly before sourcing so they persist into subsequent calls.
# shellcheck disable=SC2034 # Consumed by the sourced installer, not exported to subprocesses.
CCTOOLS_HOME="$(cd "$REPO/../.." && pwd)"
# shellcheck disable=SC2034
CCTOOLS_TEST_SOURCE=1
source "$REPO/install.sh"
load_lib
assert_eq "$(current_os)" "linux" "install: current_os linux"
load_manifest cchat
assert_eq "$DEPS" "claude" "install: load_manifest reads DEPS"
assert_eq "$(platform_ok && echo y || echo n)" "y" "install: platform_ok true for cchat on linux"
assert_eq "$(PATH=/nonexistent missing_deps)" "claude" "install: missing_deps reports gap"

# --- integration: real clone + link via the actual script process ---
PREFIX="$SANDBOX/prefix"
BIN="$SANDBOX/bin"
# Include the working tree so this exercises uncommitted consolidation changes.
SOURCE_REPO="$SANDBOX/source"
mkdir -p "$SOURCE_REPO"
(cd "$REPO/../.." && tar --exclude=.git --exclude=.pi --exclude=.superpowers -cf - .) |
  (cd "$SOURCE_REPO" && tar -xf -)
git -C "$SOURCE_REPO" init -q -b main
git -C "$SOURCE_REPO" config user.email test@example.invalid
git -C "$SOURCE_REPO" config user.name test
git -C "$SOURCE_REPO" add .
git -C "$SOURCE_REPO" commit -q -m fixture
CURRENT_BRANCH=main
out="$(CCTOOLS_REPO="file://$SOURCE_REPO" CCTOOLS_HOME="$PREFIX" CCTOOLS_BIN="$BIN" \
  CCTOOLS_BRANCH="$CURRENT_BRANCH" \
  PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=cchat,ccsession 2>&1)"
assert_eq "$([[ "$out" == *'== cctools install summary =='* ]] && echo y || echo n)" "y" "install: prints summary"
assert_eq "$([ -d "$PREFIX/.git" ] && echo y || echo n)" "y" "install: clones prefix"
assert_eq "$(readlink "$BIN/cchat")" "$PREFIX/suites/cctools/tools/cchat/cchat" "install: links cchat"
assert_eq "$(readlink "$BIN/ccsession")" "$PREFIX/suites/cctools/tools/ccsession/ccsession" "install: links ccsession"
assert_eq "$(readlink "$BIN/cctools")" "$PREFIX/bin/cctools" "install: always links cctools"
assert_eq "$([ -e "$BIN/ccbox" ] && echo y || echo n)" "n" "install: does not link unselected ccbox"

# --- idempotent re-run (existing clone -> pull, re-link) ---
CCTOOLS_REPO="file://$SOURCE_REPO" CCTOOLS_HOME="$PREFIX" CCTOOLS_BIN="$BIN" \
  CCTOOLS_BRANCH="$CURRENT_BRANCH" \
  PATH="$FAKEBIN:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO/install.sh" --tools=cchat >/dev/null 2>&1
assert_eq "$?" "0" "install: idempotent re-run succeeds"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
