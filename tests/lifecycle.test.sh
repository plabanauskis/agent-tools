#!/usr/bin/env bash
# Table-driven integration contract for every suite, with a working-tree Git fixture.
set -euo pipefail
CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
SOURCE="$SANDBOX/source with spaces"
mkdir -p "$SOURCE" "$SANDBOX/home" "$SANDBOX/fakebin"
(cd "$CHECKOUT" && tar --exclude=.git --exclude=.pi --exclude=.superpowers -cf - .) |
  (cd "$SOURCE" && tar -xf -)
git -C "$SOURCE" init -q -b testing
git -C "$SOURCE" config user.email test@example.invalid
git -C "$SOURCE" config user.name test
git -C "$SOURCE" add .
git -C "$SOURCE" commit -q -m fixture
for dep in claude codex pi jq fzf docker sysbox-runc; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SANDBOX/fakebin/$dep"
  chmod +x "$SANDBOX/fakebin/$dep"
done
export HOME="$SANDBOX/home"
export PATH="$SANDBOX/fakebin:$PATH"
PASS=0
assert() {
  local label="$1"
  shift
  if "$@"; then PASS=$((PASS + 1)); else
    echo "FAIL: $label" >&2
    exit 1
  fi
}
reject() {
  local label="$1"
  shift
  if "$@" >"$SANDBOX/rejected.log" 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
}

reject 'suite required' bash "$SOURCE/install.sh"
reject 'unknown suite' bash "$SOURCE/install.sh" --suite=unknown
reject 'duplicate suite' bash "$SOURCE/install.sh" --suite=pitools --suite=cotools
assert 'invalid suite creates no default installation' test ! -e "$HOME/.local"

for row in 'cctools CCTOOLS cchat ccsession ccbox' 'cotools COTOOLS cochat cosession cobox' 'pitools PITOOLS pichat pisession pibox'; do
  read -r suite upper chat session box <<<"$row"
  prefix="$SANDBOX/$suite prefix"
  bindir="$SANDBOX/$suite bin"
  config=("${upper}_HOME=$prefix" "${upper}_BIN=$bindir" "${upper}_REPO=file://$SOURCE" "${upper}_BRANCH=testing")
  reject "$suite invalid tool" env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --tools="$chat,unknown"
  reject "$suite conflicting selection" env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --all --tools="$chat"
  reject "$suite trailing empty tool" env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --tools="$chat,"
  reject "$suite path traversal" env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --tools=../../pitools
  assert "$suite invalid selection has no prefix side effects" test ! -e "$prefix"
  assert "$suite invalid selection has no bin side effects" test ! -e "$bindir"

  env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --tools="$chat" >"$SANDBOX/install.log" 2>&1
  assert "$suite managed clone" test -d "$prefix/.git"
  assert "$suite ownership marker" grep -qx "$suite" "$prefix/.agent-tools-suite"
  assert "$suite configured branch" test "$(git -C "$prefix" branch --show-current)" = testing
  assert "$suite root manager link" test "$(readlink "$bindir/$suite")" = "$prefix/bin/$suite"
  assert "$suite selected tool" test "$(readlink "$bindir/$chat")" = "$prefix/suites/$suite/tools/$chat/$chat"
  assert "$suite unselected session" test ! -e "$bindir/$session"
  assert "$suite opt-in box" test ! -e "$bindir/$box"
  assert "$suite symlink invocation without prefix override" test "$("$bindir/$suite" version "$chat")" = "$chat 1.0.0"
  assert "$suite source invocation" test "$(bash "$SOURCE/bin/$suite" version "$chat")" = "$chat 1.0.0"
  # shellcheck disable=SC2016 # Expanded inside the isolated Bash subprocess.
  assert "$suite sourced functions" env "${config[@]}" bash -euc 'source "$1/bin/$2"; load_manifest "$3"; test "$NAME" = "$3"' _ "$SOURCE" "$suite" "$chat"
  reject "$suite source update guard" bash "$SOURCE/bin/$suite" update
  reject "$suite source removal guard" bash "$SOURCE/bin/$suite" uninstall
  other=pitools
  [ "$suite" != pitools ] || other=cctools
  reject "$suite cannot mix suites in one installed prefix" bash "$prefix/bin/$other" version
  assert "$suite source remains intact" test -d "$SOURCE/.git"

  env "${config[@]}" "$bindir/$suite" enable "$session" >"$SANDBOX/enable.log"
  assert "$suite enable" test -L "$bindir/$session"
  env "${config[@]}" "$bindir/$suite" disable "$session" >"$SANDBOX/disable.log"
  assert "$suite disable" test ! -e "$bindir/$session"
  reject "$suite unknown enable" env "${config[@]}" "$bindir/$suite" enable ../cotools

  printf '%s\n' "$suite" >>"$SOURCE/update-fixture"
  git -C "$SOURCE" add update-fixture
  git -C "$SOURCE" commit -q -m "update $suite fixture"
  env "${config[@]}" "$bindir/$suite" update >"$SANDBOX/update.log" 2>&1
  assert "$suite updates clone root" test "$(git -C "$prefix" rev-parse HEAD)" = "$(git -C "$SOURCE" rev-parse HEAD)"
  assert "$suite re-links enabled tool" grep -q "re-linked $chat" "$SANDBOX/update.log"
  assert "$suite update keeps other tools disabled" test ! -e "$bindir/$session"
  printf 'local edit\n' >>"$prefix/update-fixture"
  reject "$suite dirty update" env "${config[@]}" "$bindir/$suite" update
  assert "$suite keeps local edits" grep -q 'local edit' "$prefix/update-fixture"
  git -C "$prefix" checkout -- update-fixture
  printf 'staged edit\n' >>"$prefix/update-fixture"
  git -C "$prefix" add update-fixture
  reject "$suite staged update" env "${config[@]}" "$bindir/$suite" update
  git -C "$prefix" reset -q HEAD -- update-fixture
  git -C "$prefix" checkout -- update-fixture
  env "${config[@]}" bash "$SOURCE/suites/$suite/install.sh" --tools="$chat" >"$SANDBOX/reinstall.log" 2>&1
  assert "$suite repeated installer" test -L "$bindir/$chat"

  foreign="$SANDBOX/foreign-$suite"
  printf '#!/usr/bin/env bash\n' >"$foreign"
  ln -sf "$foreign" "$bindir/$suite"
  ln -sf "$foreign" "$bindir/$session"
  # shellcheck disable=SC2016 # Expanded inside the isolated Bash subprocess.
  env "${config[@]}" bash -euc 'source "$1/bin/$2"; remove_prefix' _ "$SOURCE" "$suite" >"$SANDBOX/remove.log"
  assert "$suite owned prefix removed" test ! -e "$prefix"
  assert "$suite owned tool link removed" test ! -L "$bindir/$chat"
  assert "$suite foreign manager preserved" test "$(readlink "$bindir/$suite")" = "$foreign"
  assert "$suite foreign session preserved" test "$(readlink "$bindir/$session")" = "$foreign"
  assert "$suite source clone preserved" test -d "$SOURCE/.git"
  assert "$suite foreign target preserved" test -f "$foreign"

  # Legacy prefix/source clones cannot be overwritten by re-running the installer.
  mkdir -p "$prefix"
  printf 'keep\n' >"$prefix/important"
  reject "$suite unmanaged existing prefix" env "${config[@]}" bash "$SOURCE/install.sh" --suite="$suite" --tools="$chat"
  assert "$suite unmanaged data preserved" grep -qx keep "$prefix/important"
done
# Install all suites side by side into a shared bin directory, then remove just one.
shared_bin="$SANDBOX/shared bin"
for row in 'cctools CCTOOLS cchat' 'cotools COTOOLS cochat' 'pitools PITOOLS pichat'; do
  read -r suite upper chat <<<"$row"
  env "${upper}_HOME=$SANDBOX/side-$suite" "${upper}_BIN=$shared_bin" \
    "${upper}_REPO=file://$SOURCE" "${upper}_BRANCH=testing" \
    bash "$SOURCE/install.sh" --suite="$suite" --tools="$chat" >"$SANDBOX/side.log" 2>&1
done
# shellcheck disable=SC2016 # Expanded by the child shell.
PITOOLS_BIN="$shared_bin" bash -euc 'source "$1/bin/pitools"; remove_prefix' _ "$SANDBOX/side-pitools" >"$SANDBOX/side-remove.log"
assert 'Pi prefix removed independently' test ! -e "$SANDBOX/side-pitools"
assert 'Pi manager link removed independently' test ! -L "$shared_bin/pitools"
for row in 'cctools cchat' 'cotools cochat'; do
  read -r suite chat <<<"$row"
  assert "$suite sibling clone intact" test -d "$SANDBOX/side-$suite/.git"
  assert "$suite sibling link intact" test -L "$shared_bin/$chat"
  assert "$suite sibling manager usable" test "$("$shared_bin/$suite" version "$chat")" = "$chat 1.0.0"
done
printf '%d passed, 0 failed\n' "$PASS"
