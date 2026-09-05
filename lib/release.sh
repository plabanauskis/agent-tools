#!/usr/bin/env bash
# Shared per-tool release functions. RELEASE_ROOT is the suite directory.
is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

bump_version() {
  local tool="$1" version="$2" variable='' file temporary
  printf '%s\n' "$version" >"$RELEASE_ROOT/tools/$tool/VERSION"
  case "$tool" in
    ccbox) variable=CCBOX_VERSION ;;
    cobox) variable=COBOX_VERSION ;;
    pibox) variable=PIBOX_VERSION ;;
  esac
  file="$RELEASE_ROOT/tools/$tool/bin/$tool"
  if [ -n "$variable" ] && [ -f "$file" ]; then
    temporary="$(mktemp)"
    sed -E "s/^${variable}=\"[^\"]*\"/${variable}=\"$version\"/" "$file" >"$temporary"
    cat "$temporary" >"$file" # Preserve executable mode; works with BSD sed too.
    rm -f "$temporary"
  fi
}

prepend_changelog() {
  local changelog="$RELEASE_ROOT/tools/$1/CHANGELOG.md" temporary
  temporary="$(mktemp)"
  {
    head -n1 "$changelog"
    printf '\n## %s — %s\n\n- TODO: summarize changes.\n' "$2" "$3"
    tail -n +2 "$changelog"
  } >"$temporary"
  cat "$temporary" >"$changelog"
  rm -f "$temporary"
}

usage() {
  cat <<'EOF'
Usage: scripts/release.sh <tool> <version> [--gh] [--date=YYYY-MM-DD]
Bump VERSION and CHANGELOG, commit, and tag <tool>-vX.Y.Z. Requires a clean tree.
Edit the generated changelog TODO before pushing (amend commit and recreate tag).
--gh explicitly pushes the commit/tag and creates a GitHub draft release.
EOF
}

main() {
  local tool="${1:-}" version="${2:-}" do_gh=0 date_str='' argument tag
  shift 2 2>/dev/null || {
    usage
    return 1
  }
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
  known_tool "$tool" || {
    echo "release.sh: unknown tool '$tool'" >&2
    return 1
  }
  is_semver "$version" || {
    echo "release.sh: '$version' is not X.Y.Z" >&2
    return 1
  }
  tag="$tool-v$version"
  if [ -n "$(git -C "$RELEASE_ROOT" status --porcelain)" ]; then
    echo 'release.sh: requires a clean working tree and index' >&2
    return 1
  fi
  if git -C "$RELEASE_ROOT" rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "release.sh: tag '$tag' already exists" >&2
    return 1
  fi
  if [ "$do_gh" = 1 ]; then command -v gh >/dev/null || return 1; fi
  [ -n "$date_str" ] || date_str="$(date +%Y-%m-%d)"
  bump_version "$tool" "$version"
  prepend_changelog "$tool" "$version" "$date_str"
  git -C "$RELEASE_ROOT" add "tools/$tool/VERSION" "tools/$tool/CHANGELOG.md"
  case "$tool" in *box) git -C "$RELEASE_ROOT" add "tools/$tool/bin/$tool" ;; esac
  git -C "$RELEASE_ROOT" commit -m "release($tool): $version"
  git -C "$RELEASE_ROOT" tag -a "$tag" -m "$tool $version"
  echo "Committed and tagged $tag. Edit the changelog TODO before publication."
  echo "Push with: git push origin HEAD $tag"
  if [ "$do_gh" = 1 ]; then
    git -C "$RELEASE_ROOT" push origin HEAD "$tag"
    (cd "$RELEASE_ROOT" && gh release create "$tag" --verify-tag --draft --title "$tool $version" \
      --notes "See suites/$SUITE/tools/$tool/CHANGELOG.md; complete its TODO before publishing this draft.")
  fi
}
