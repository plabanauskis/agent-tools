#!/usr/bin/env bash
# Exercises release helpers against a disposable COTOOLS_HOME. No release
# command, Git mutation, tag, or remote request is performed here.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export COTOOLS_HOME="$SANDBOX/repo"
mkdir -p "$COTOOLS_HOME/tools/cochat" "$COTOOLS_HOME/tools/cobox/bin"
printf '1.0.0\n' >"$COTOOLS_HOME/tools/cochat/VERSION"
printf '# Changelog — cochat\n\n## 1.0.0 — 2026-08-26\n\n- Initial.\n' \
  >"$COTOOLS_HOME/tools/cochat/CHANGELOG.md"
printf '1.0.0\n' >"$COTOOLS_HOME/tools/cobox/VERSION"
printf '# Changelog — cobox\n\n## 1.0.0 — 2026-08-26\n\n- Initial.\n' \
  >"$COTOOLS_HOME/tools/cobox/CHANGELOG.md"
printf '#!/usr/bin/env bash\nCOBOX_VERSION="1.0.0"\n' \
  >"$COTOOLS_HOME/tools/cobox/bin/cobox"

# shellcheck source=/dev/null
source "$REPO/scripts/release.sh"
# Unit helpers operate on the isolated suite fixture, not the actual checkout.
# shellcheck disable=SC2034 # Consumed by dynamically sourced release helpers.
RELEASE_ROOT="$COTOOLS_HOME"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
assert_eq() { # <got> <want> <mutation>
  if [ "$1" = "$2" ]; then
    pass
  else
    fail "$3 (got [$1] want [$2])"
  fi
}
assert_file_contains() { # <file> <needle> <mutation>
  if grep -Fq -- "$2" "$1"; then
    pass
  else
    fail "$3"
  fi
}

# A looser semver predicate would admit tags that release tooling cannot name.
assert_eq "$(is_semver 1.2.3 && echo y || echo n)" "y" \
  "is_semver: accepts a complete semantic version"
assert_eq "$(is_semver v1.2 && echo y || echo n)" "n" \
  "is_semver: rejects a tag-prefixed incomplete version"

# The cochat release state must update the version and insert its entry before
# the prior changelog content, without rewriting the human-facing title.
bump_version cochat 1.1.0
assert_eq "$(<"$COTOOLS_HOME/tools/cochat/VERSION")" "1.1.0" \
  "bump_version cochat: writes the requested semantic version"
prepend_changelog cochat 1.1.0 2026-08-27
assert_eq "$(head -n1 "$COTOOLS_HOME/tools/cochat/CHANGELOG.md")" "# Changelog — cochat" \
  "prepend_changelog cochat: preserves the changelog title"
assert_file_contains "$COTOOLS_HOME/tools/cochat/CHANGELOG.md" "## 1.1.0 — 2026-08-27" \
  "prepend_changelog cochat: inserts the new dated release heading"
assert_file_contains "$COTOOLS_HOME/tools/cochat/CHANGELOG.md" "## 1.0.0 — 2026-08-26" \
  "prepend_changelog cochat: retains the previous release entry"

# cobox has two version consumers; updating only VERSION leaves the image's
# runtime metadata stale.
bump_version cobox 1.1.0
assert_eq "$(<"$COTOOLS_HOME/tools/cobox/VERSION")" "1.1.0" \
  "bump_version cobox: writes VERSION"
assert_file_contains "$COTOOLS_HOME/tools/cobox/bin/cobox" 'COBOX_VERSION="1.1.0"' \
  "bump_version cobox: synchronizes the embedded launcher version"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
