#!/usr/bin/env bash
# Per-tool release helper: bump VERSION + CHANGELOG, commit, tag <tool>-vX.Y.Z,
# and (with --gh) cut a GitHub release. Functions remain sourceable for tests.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

RELEASE_ROOT="${PITOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

bump_version() { # <tool> <version>
  echo "$2" >"$RELEASE_ROOT/tools/$1/VERSION"
  # Keep pibox's embedded version in sync with its release metadata.
  if [ "$1" = "pibox" ] && [ -f "$RELEASE_ROOT/tools/pibox/bin/pibox" ]; then
    sed -i -E "s/^PIBOX_VERSION=\"[^\"]*\"/PIBOX_VERSION=\"$2\"/" \
      "$RELEASE_ROOT/tools/pibox/bin/pibox"
  fi
}

prepend_changelog() { # <tool> <version> <date>
  local changelog="$RELEASE_ROOT/tools/$1/CHANGELOG.md" temporary
  temporary="$(mktemp)"
  {
    head -n1 "$changelog"
    printf '\n## %s — %s\n\n- TODO: summarize changes.\n' "$2" "$3"
    tail -n +2 "$changelog"
  } >"$temporary"
  mv "$temporary" "$changelog"
}

usage() {
  cat <<'EOF'
release.sh — cut a per-tool release

Usage:
  scripts/release.sh <tool> <version> [--gh] [--date=YYYY-MM-DD]

Bumps tools/<tool>/VERSION + CHANGELOG.md, commits, and tags <tool>-vX.Y.Z.
--gh also runs 'gh release create <tool>-vX.Y.Z'. Edit the CHANGELOG TODO line
before pushing.
EOF
}

main() {
  local tool="${1:-}" version="${2:-}" do_gh=0 date_str=''
  shift 2 2>/dev/null || {
    usage
    return 1
  }
  local argument
  for argument in "$@"; do
    case "$argument" in
      --gh) do_gh=1 ;;
      --date=*) date_str="${argument#--date=}" ;;
      *)
        echo "release.sh: unknown arg '$argument'" >&2
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
  [ "$tool" = "pibox" ] && git -C "$RELEASE_ROOT" add "tools/pibox/bin/pibox"
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
