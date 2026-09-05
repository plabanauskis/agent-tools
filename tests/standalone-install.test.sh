#!/usr/bin/env bash
# Public bootstrap contract: stdin and standalone downloads need no local libraries.
set -euo pipefail
CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
SOURCE="$SANDBOX/source with spaces"
mkdir -p "$SOURCE" "$SANDBOX/download" "$SANDBOX/empty" "$SANDBOX/bootstrap tmp" "$SANDBOX/home"
(cd "$CHECKOUT" && tar --exclude=.git --exclude=.pi --exclude=.superpowers -cf - .) |
  (cd "$SOURCE" && tar -xf -)
git -C "$SOURCE" init -q -b public-test
git -C "$SOURCE" config user.email test@example.invalid
git -C "$SOURCE" config user.name test
git -C "$SOURCE" add .
git -C "$SOURCE" commit -q -m fixture
cp "$SOURCE/install.sh" "$SANDBOX/download/install.sh"
cd "$SANDBOX/empty"
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
  if "$@" >"$SANDBOX/reject.log" 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
}
bootstrap_clean() {
  [ -z "$(find "$SANDBOX/bootstrap tmp" -mindepth 1 -print)" ]
}

for row in 'cctools CCTOOLS cchat' 'cotools COTOOLS cochat' 'pitools PITOOLS pichat'; do
  read -r suite upper chat <<<"$row"
  for mode in stdin downloaded; do
    prefix="$SANDBOX/$suite-$mode prefix"
    bindir="$SANDBOX/$suite-$mode bin"
    config=("HOME=$SANDBOX/home" "TMPDIR=$SANDBOX/bootstrap tmp"
      "${upper}_HOME=$prefix" "${upper}_BIN=$bindir"
      "${upper}_REPO=file://$SOURCE" "${upper}_BRANCH=public-test")
    if [ "$mode" = stdin ]; then
      env "${config[@]}" bash -s -- --suite="$suite" --tools="$chat" --force \
        <"$SANDBOX/download/install.sh" >"$SANDBOX/install.log" 2>&1 || {
        cat "$SANDBOX/install.log"
        exit 1
      }
    else
      env "${config[@]}" bash "$SANDBOX/download/install.sh" --suite="$suite" --tools="$chat" --force \
        >"$SANDBOX/install.log" 2>&1 || {
        cat "$SANDBOX/install.log"
        exit 1
      }
    fi
    assert "$suite $mode clones a managed prefix" test -d "$prefix/.git"
    assert "$suite $mode respects branch override" test "$(git -C "$prefix" branch --show-current)" = public-test
    assert "$suite $mode retains upstream override" test "$(git -C "$prefix" remote get-url origin)" = "file://$SOURCE"
    assert "$suite $mode marks prefix ownership" grep -qx "$suite" "$prefix/.agent-tools-suite"
    assert "$suite $mode links selected tool" test "$(readlink "$bindir/$chat")" = "$prefix/suites/$suite/tools/$chat/$chat"
    assert "$suite $mode manager works" test "$("$bindir/$suite" version "$chat")" = "$chat 1.0.0"
    assert "$suite $mode links only manager and selected tool" test "$(find "$bindir" -type l | wc -l | tr -d ' ')" = 2
    assert "$suite $mode removes bootstrap checkout" bootstrap_clean
    # Repeat the downloaded/piped install without destroying existing state.
    env "${config[@]}" bash -s -- --suite="$suite" --tools="$chat" --force \
      <"$SANDBOX/download/install.sh" >"$SANDBOX/repeat.log" 2>&1 || {
      cat "$SANDBOX/repeat.log"
      exit 1
    }
    assert "$suite $mode repeated install retains tool" test -L "$bindir/$chat"
    assert "$suite $mode repeated install cleans bootstrap" bootstrap_clean
  done
done

config=("HOME=$SANDBOX/home" "TMPDIR=$SANDBOX/bootstrap tmp" "PITOOLS_HOME=$SANDBOX/rejected prefix"
  "PITOOLS_BIN=$SANDBOX/rejected bin" "PITOOLS_REPO=file://$SOURCE" "PITOOLS_BRANCH=public-test")
reject 'invalid selection through stdin' env "${config[@]}" bash -s -- --suite=pitools --tools=unknown <"$SANDBOX/download/install.sh"
assert 'invalid selection leaves no prefix' test ! -e "$SANDBOX/rejected prefix"
assert 'invalid selection leaves no links' test ! -e "$SANDBOX/rejected bin"
assert 'invalid selection cleans bootstrap' bootstrap_clean
reject 'failed clone' env "${config[@]}" PITOOLS_REPO="$SANDBOX/nonexistent.git" \
  bash "$SANDBOX/download/install.sh" --suite=pitools --tools=pichat
assert 'failed clone cleans bootstrap' bootstrap_clean
assert 'failed clone leaves no prefix' test ! -e "$SANDBOX/rejected prefix"

# Help and invalid bootstrap arguments must not invoke Git or require a checkout.
mkdir "$SANDBOX/fakebin"
# shellcheck disable=SC2016 # Expanded by the fake Git process, not this test.
printf '#!/usr/bin/env bash\nprintf invoked >"$GIT_RECORD"\nexit 1\n' >"$SANDBOX/fakebin/git"
chmod +x "$SANDBOX/fakebin/git"
PATH="$SANDBOX/fakebin:$PATH" GIT_RECORD="$SANDBOX/git-record" bash "$SANDBOX/download/install.sh" --help >"$SANDBOX/help"
assert 'standalone help needs no Git' test ! -e "$SANDBOX/git-record"
reject 'unknown suite rejected before Git' env PATH="$SANDBOX/fakebin:$PATH" GIT_RECORD="$SANDBOX/git-record" \
  bash "$SANDBOX/download/install.sh" --suite=unknown
reject 'unknown flag rejected before Git' env PATH="$SANDBOX/fakebin:$PATH" GIT_RECORD="$SANDBOX/git-record" \
  bash "$SANDBOX/download/install.sh" --suite=pitools --unknown
assert 'invalid arguments need no Git' test ! -e "$SANDBOX/git-record"
printf '%d passed, 0 failed\n' "$PASS"
