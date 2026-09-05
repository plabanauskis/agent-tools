#!/usr/bin/env bash
# Per-tool release helper: bump VERSION + CHANGELOG, commit, tag <tool>-vX.Y.Z,
# and (with --gh) cut a GitHub release. Bump fns are sourceable for tests; git
# side effects run only in main. Honors CCTOOLS_HOME (default = repo root).
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

RELEASE_ROOT="${CCTOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

bump_version() { # <tool> <version>
  echo "$2" >"$RELEASE_ROOT/tools/$1/VERSION"
  # Keep ccbox's embedded CCBOX_VERSION in sync so 'ccbox version' matches.
  if [ "$1" = "ccbox" ] && [ -f "$RELEASE_ROOT/tools/ccbox/bin/ccbox" ]; then
    sed -i -E "s/^CCBOX_VERSION=\"[^\"]*\"/CCBOX_VERSION=\"$2\"/" \
      "$RELEASE_ROOT/tools/ccbox/bin/ccbox"
  fi
}

prepend_changelog() { # <tool> <version> <date>
  local cl="$RELEASE_ROOT/tools/$1/CHANGELOG.md" tmp
  tmp="$(mktemp)"
  # Title line stays first; insert the new entry directly beneath it.
  {
    head -n1 "$cl"
    printf '\n## %s — %s\n\n- TODO: summarize changes.\n' "$2" "$3"
    tail -n +2 "$cl"
  } >"$tmp"
  mv "$tmp" "$cl"
}

usage() {
  cat <<'EOF'
release.sh — cut a per-tool release

Usage:
  scripts/release.sh <tool> <version> [--gh] [--date=YYYY-MM-DD]

Bumps tools/<tool>/VERSION + CHANGELOG.md, commits, and tags <tool>-vX.Y.Z.
--gh also runs 'gh release create <tool>-vX.Y.Z'. Edit the CHANGELOG's TODO line
before pushing.
EOF
}

main() {
  local tool="${1:-}" version="${2:-}" do_gh=0 date_str=''
  shift 2 2>/dev/null || {
    usage
    return 1
  }
  local a
  for a in "$@"; do
    case "$a" in
      --gh) do_gh=1 ;;
      --date=*) date_str="${a#--date=}" ;;
      *)
        echo "release.sh: unknown arg '$a'" >&2
        return 1
        ;;
    esac
  done
  [ -d "$RELEASE_ROOT/tools/$tool" ] || {
    echo "release.sh: unknown tool '$tool'" >&2
    return 1
  }
  is_semver "$version" || {
    echo "release.sh: '$version' is not X.Y.Z" >&2
    return 1
  }
  [ -n "$date_str" ] || date_str="$(date +%Y-%m-%d)"

  bump_version "$tool" "$version"
  prepend_changelog "$tool" "$version" "$date_str"
  echo "Bumped $tool -> $version (edit the CHANGELOG TODO line, then continue)."

  local tag="$tool-v$version"
  git -C "$RELEASE_ROOT" add "tools/$tool/VERSION" "tools/$tool/CHANGELOG.md"
  [ "$tool" = "ccbox" ] && git -C "$RELEASE_ROOT" add "tools/ccbox/bin/ccbox"
  git -C "$RELEASE_ROOT" commit -m "release($tool): $version"
  git -C "$RELEASE_ROOT" tag -a "$tag" -m "$tool $version"
  echo "Committed and tagged $tag. Push with: git push origin HEAD $tag"

  if [ "$do_gh" = 1 ]; then
    command -v gh >/dev/null 2>&1 || {
      echo "release.sh: gh not installed" >&2
      return 1
    }
    gh release create "$tag" --title "$tool $version" \
      --notes "See tools/$tool/CHANGELOG.md"
  fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
