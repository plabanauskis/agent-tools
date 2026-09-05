#!/usr/bin/env bash
# Tests for release.sh bump helpers. Sources the script (guard keeps main from
# running) and exercises bump_version/prepend_changelog against a temp copy of
# a tool dir, so no real commit/tag happens.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
# Stage a fake repo root with one tool dir.
export CCTOOLS_HOME="$SANDBOX/repo"
mkdir -p "$CCTOOLS_HOME/tools/cchat"
echo "1.0.0" >"$CCTOOLS_HOME/tools/cchat/VERSION"
printf '# Changelog — cchat\n\n## 1.0.0 — 2026-06-24\n\n- Initial.\n' >"$CCTOOLS_HOME/tools/cchat/CHANGELOG.md"

# shellcheck source=/dev/null
source "$REPO/scripts/release.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
# shellcheck disable=SC2015  # ok() always succeeds; C (bad) only runs when A fails
assert_eq() { [ "$1" = "$2" ] && ok || bad "$3 (got [$1] want [$2])"; }

assert_eq "$(is_semver 1.2.3 && echo y || echo n)" "y" "is_semver: accepts 1.2.3"
assert_eq "$(is_semver v1.2 && echo y || echo n)" "n" "is_semver: rejects v1.2"

bump_version cchat 1.1.0
assert_eq "$(cat "$CCTOOLS_HOME/tools/cchat/VERSION")" "1.1.0" "bump_version: writes new version"

prepend_changelog cchat 1.1.0 2026-07-01
head1="$(head -n1 "$CCTOOLS_HOME/tools/cchat/CHANGELOG.md")"
assert_eq "$head1" "# Changelog — cchat" "prepend_changelog: keeps title first"
# shellcheck disable=SC2015  # ok() always succeeds; bad() only runs when grep fails
grep -q "## 1.1.0 — 2026-07-01" "$CCTOOLS_HOME/tools/cchat/CHANGELOG.md" && ok || bad "prepend_changelog: adds new heading"
# shellcheck disable=SC2015  # ok() always succeeds; bad() only runs when grep fails
grep -q "## 1.0.0 — 2026-06-24" "$CCTOOLS_HOME/tools/cchat/CHANGELOG.md" && ok || bad "prepend_changelog: keeps old entry"

# ---- ccbox CCBOX_VERSION sync ----
mkdir -p "$CCTOOLS_HOME/tools/ccbox/bin"
printf '#!/usr/bin/env bash\nCCBOX_VERSION="1.0.0"\n' >"$CCTOOLS_HOME/tools/ccbox/bin/ccbox"
echo "1.0.0" >"$CCTOOLS_HOME/tools/ccbox/VERSION"
printf '# Changelog — ccbox\n\n## 1.0.0 — 2026-06-24\n\n- Initial.\n' \
  >"$CCTOOLS_HOME/tools/ccbox/CHANGELOG.md"

bump_version ccbox 1.1.0
assert_eq "$(cat "$CCTOOLS_HOME/tools/ccbox/VERSION")" "1.1.0" \
  "bump_version ccbox: writes VERSION"
# shellcheck disable=SC2015  # ok() always succeeds; bad() only runs when grep fails
grep -q 'CCBOX_VERSION="1.1.0"' "$CCTOOLS_HOME/tools/ccbox/bin/ccbox" &&
  ok || bad "bump_version ccbox: updates CCBOX_VERSION in bin/ccbox"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
