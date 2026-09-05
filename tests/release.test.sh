#!/usr/bin/env bash
# Exercise actual release entrypoints in a disposable monorepo (never publish).
set -euo pipefail
CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
(cd "$CHECKOUT" && tar --exclude=.git --exclude=.pi --exclude=.superpowers -cf - .) |
  (cd "$SANDBOX" && tar -xf -)
git -C "$SANDBOX" init -q -b main
git -C "$SANDBOX" config user.email test@example.invalid
git -C "$SANDBOX" config user.name test
git -C "$SANDBOX" add .
git -C "$SANDBOX" commit -q -m fixture
unset CCTOOLS_HOME COTOOLS_HOME PITOOLS_HOME
for entry in 'cctools cchat' 'cotools cochat' 'pitools pichat'; do
  read -r suite tool <<<"$entry"
  bash "$SANDBOX/scripts/release.sh" "$tool" 1.2.3 --date=2026-09-05 >/dev/null
  test "$(git -C "$SANDBOX" describe --exact-match --tags HEAD)" = "$tool-v1.2.3"
  test "$(cat "$SANDBOX/suites/$suite/tools/$tool/VERSION")" = 1.2.3
  test -z "$(git -C "$SANDBOX" status --porcelain)"
  before="$(git -C "$SANDBOX" rev-parse HEAD)"
  if bash "$SANDBOX/scripts/release.sh" "$tool" 1.2.3 >/dev/null 2>&1; then
    echo 'FAIL: duplicate release tag accepted' >&2
    exit 1
  fi
  test "$(git -C "$SANDBOX" rev-parse HEAD)" = "$before"
  test -z "$(git -C "$SANDBOX" status --porcelain)"
done
# Suite wrapper shares the same implementation and keeps embedded versions in sync.
bash "$SANDBOX/suites/cctools/scripts/release.sh" ccbox 1.2.0 >/dev/null
grep -q '^CCBOX_VERSION="1.2.0"' "$SANDBOX/suites/cctools/tools/ccbox/bin/ccbox"
# A foreign staged change must not be swept into a release commit.
printf 'local edit\n' >>"$SANDBOX/README.md"
git -C "$SANDBOX" add README.md
before="$(git -C "$SANDBOX" rev-parse HEAD)"
if bash "$SANDBOX/scripts/release.sh" pichat 1.2.4 >/dev/null 2>&1; then
  echo 'FAIL: release accepted unrelated staged work' >&2
  exit 1
fi
test "$(git -C "$SANDBOX" rev-parse HEAD)" = "$before"
test "$(cat "$SANDBOX/suites/pitools/tools/pichat/VERSION")" = 1.2.3
printf 'release entrypoints: PASS (all suites, duplicate tags, embedded version, dirty guard)\n'
