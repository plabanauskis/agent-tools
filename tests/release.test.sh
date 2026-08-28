#!/usr/bin/env bash
# Exercises release helpers against a disposable PITOOLS_HOME. No release
# command, Git mutation, tag, or remote request is performed here.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export PITOOLS_HOME="$SANDBOX/repo"
mkdir -p "$PITOOLS_HOME/tools/pichat" "$PITOOLS_HOME/tools/pibox/bin"
printf '1.0.0\n' >"$PITOOLS_HOME/tools/pichat/VERSION"
printf '# Changelog — pichat\n\n## 1.0.0 — 2026-08-26\n\n- Initial.\n' \
  >"$PITOOLS_HOME/tools/pichat/CHANGELOG.md"
printf '1.0.0\n' >"$PITOOLS_HOME/tools/pibox/VERSION"
printf '# Changelog — pibox\n\n## 1.0.0 — 2026-08-26\n\n- Initial.\n' \
  >"$PITOOLS_HOME/tools/pibox/CHANGELOG.md"
printf '#!/usr/bin/env bash\nPIBOX_VERSION="1.0.0"\n' \
  >"$PITOOLS_HOME/tools/pibox/bin/pibox"

# shellcheck source=/dev/null
source "$REPO/scripts/release.sh"

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

# The pichat release state must update the version and insert its entry before
# the prior changelog content, without rewriting the human-facing title.
bump_version pichat 1.1.0
assert_eq "$(<"$PITOOLS_HOME/tools/pichat/VERSION")" "1.1.0" \
  "bump_version pichat: writes the requested semantic version"
prepend_changelog pichat 1.1.0 2026-08-27
assert_eq "$(head -n1 "$PITOOLS_HOME/tools/pichat/CHANGELOG.md")" "# Changelog — pichat" \
  "prepend_changelog pichat: preserves the changelog title"
assert_file_contains "$PITOOLS_HOME/tools/pichat/CHANGELOG.md" "## 1.1.0 — 2026-08-27" \
  "prepend_changelog pichat: inserts the new dated release heading"
assert_file_contains "$PITOOLS_HOME/tools/pichat/CHANGELOG.md" "## 1.0.0 — 2026-08-26" \
  "prepend_changelog pichat: retains the previous release entry"

# pibox has two version consumers; updating only VERSION leaves the image's
# runtime metadata stale.
bump_version pibox 1.1.0
assert_eq "$(<"$PITOOLS_HOME/tools/pibox/VERSION")" "1.1.0" \
  "bump_version pibox: writes VERSION"
assert_file_contains "$PITOOLS_HOME/tools/pibox/bin/pibox" 'PIBOX_VERSION="1.1.0"' \
  "bump_version pibox: synchronizes the embedded launcher version"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
