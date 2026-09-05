#!/usr/bin/env bash
# Asset contract: rendered Node Trail marks remain legible, branded, and portable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

readonly ACCENT='#10A37F'
readonly LIGHT_INK='#16181D'
readonly DARK_INK='#F4F1EA'

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=1
}

need_file() {
  [ -f "$1" ] || fail "missing asset: $1"
}

need_readme() {
  [ -f "$1" ] || fail "missing README: $1"
}

need_text() {
  local file="$1" text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    fail "missing required documentation text in $file: $text"
  fi
}

has_rendered_color() {
  local file="$1" color="$2"
  # Consume the histogram fully: grep -q can SIGPIPE convert under pipefail.
  convert -background none "$file" -resize 512x512 -depth 8 -format '%c' histogram:info:- |
    grep -i "${color#\#}" >/dev/null
}

for tool in cochat cosession cobox; do
  for asset in icon.svg icon-dark.svg logo.svg logo-dark.svg og-image.svg og-image.png; do
    need_file "tools/$tool/assets/$asset"
  done
done

# README contracts: keep public installation, independence, state, and isolation
# statements present without constraining the explanatory prose around them.
for readme in README.md tools/cochat/README.md tools/cosession/README.md tools/cobox/README.md; do
  need_readme "$readme"
done
need_text README.md 'curl -fsSL https://raw.githubusercontent.com/plabanauskis/agent-tools/main/install.sh | bash -s -- --suite=cotools'
need_text README.md 'bash install.sh --suite=cotools'
need_text README.md 'No GitHub account or sudo is needed'
need_text README.md 'not affiliated with or endorsed by OpenAI'
need_text README.md 'fetches and prunes, then hard-resets'
need_text README.md 'COTOOLS_REPO'
need_text README.md 'COTOOLS_BRANCH'
need_text tools/cosession/README.md 'CODEX_HOME'
need_text tools/cosession/README.md "\$HOME/.codex"
need_text tools/cobox/README.md '--dangerously-bypass-approvals-and-sandbox'
need_text tools/cobox/README.md 'never mounts the host Docker socket'
need_text tools/cobox/README.md 'narrow the blast radius'
need_text tools/cobox/README.md 'does not mount the host OS keyring'
need_text tools/cobox/README.md 'usable file-backed state'
need_text tools/cobox/README.md 'COBOX_SHARE_DIR'

# Do not let the active source and public docs regress to the prior suite's
# names, runtime, authentication, or accent. Historical port records and the
# MIT attribution are intentionally excluded.
legacy_name_hits() { # <root>: 0=matches, 1=clean, >1=search error
  rg -n -i --hidden \
    --glob '!.git/**' \
    --glob '!.worktrees/**' \
    --glob '!.superpowers/**' \
    --glob '!docs/superpowers/**' \
    --glob '!LICENSE' \
    --glob '!tests/assets.test.sh' \
    -e '(^|[^[:alnum:]])(cctools|cchat|ccsession|ccbox)([^[:alnum:]]|$)' \
    -e 'Claude Code|~/.claude|dangerously-skip-permissions|\bclaude (resume|login)' \
    -e 'ANTHROPIC_(API_KEY|AUTH_TOKEN)' \
    -e '#D97757' "$1"
}

legacy_status=0
legacy_hits="$(legacy_name_hits .)" || legacy_status=$?
if [ "$legacy_status" -gt 1 ]; then
  fail "legacy-name audit failed (rg exit $legacy_status)"
elif [ -n "$legacy_hits" ]; then
  fail "legacy public/runtime/auth/color term outside approved historical context:\n$legacy_hits"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

for tool in cochat cosession cobox; do
  asset_dir="tools/$tool/assets"

  [ "$(identify -format '%wx%h' "$asset_dir/icon.svg")" = '128x128' ] ||
    fail "icon dimensions must retain the source 128x128 canvas: $asset_dir/icon.svg"
  [ "$(identify -format '%wx%h' "$asset_dir/icon-dark.svg")" = '128x128' ] ||
    fail "dark icon dimensions must retain the source 128x128 canvas: $asset_dir/icon-dark.svg"
  logo_size='360x160'
  [ "$tool" = 'cosession' ] && logo_size='480x160'
  for variant in logo.svg logo-dark.svg; do
    [ "$(identify -format '%wx%h' "$asset_dir/$variant")" = "$logo_size" ] ||
      fail "wordmark dimensions must retain the source canvas: $asset_dir/$variant"
  done
  [ "$(identify -format '%wx%h' "$asset_dir/og-image.svg")" = '1280x640' ] ||
    fail "social SVG must be 1280x640: $asset_dir/og-image.svg"

  for svg in "$asset_dir"/*.svg; do
    xmllint --noout "$svg" || fail "invalid SVG XML: $svg"
    if rg -qi 'cchat|ccsession|ccbox|claude|D97757|openai' "$svg"; then
      fail "legacy or prohibited name/color in: $svg"
    fi
    if ! has_rendered_color "$svg" "$ACCENT"; then
      fail "missing rendered Node Trail accent in: $svg"
    fi
  done

  for variant in icon.svg logo.svg; do
    if ! has_rendered_color "$asset_dir/$variant" "$LIGHT_INK"; then
      fail "light mark is not readable in dark ink: $asset_dir/$variant"
    fi
  done
  for variant in icon-dark.svg logo-dark.svg; do
    if ! has_rendered_color "$asset_dir/$variant" "$DARK_INK"; then
      fail "dark mark is not readable in light ink: $asset_dir/$variant"
    fi
  done

  for variant in icon.svg icon-dark.svg logo.svg logo-dark.svg; do
    rendered="$(mktemp "${TMPDIR:-/tmp}/cotools-asset.XXXXXX.png")"
    convert -background none "$asset_dir/$variant" -depth 8 "$rendered"
    [ "$(identify -format '%[pixel:p{0,0}]' "$rendered")" = 'srgba(0,0,0,0)' ] ||
      fail "mark must retain a transparent canvas: $asset_dir/$variant"
    rm -f "$rendered"
  done

  [ "$(identify -format '%wx%h' "$asset_dir/og-image.png")" = '1280x640' ] ||
    fail "social PNG must be 1280x640: $asset_dir/og-image.png"
  [ "$(identify -format '%[pixel:p{0,0}]' "$asset_dir/og-image.png")" = 'srgba(20,22,27,1)' ] ||
    fail "social PNG must have an opaque #14161B background: $asset_dir/og-image.png"

  rendered="$(mktemp "${TMPDIR:-/tmp}/cotools-social.XXXXXX.png")"
  convert "$asset_dir/og-image.svg" "$rendered"
  [ "$(compare -metric AE "$asset_dir/og-image.png" "$rendered" null: 2>&1)" = '0' ] ||
    fail "social PNG must be reproducible from its SVG source: $asset_dir/og-image.png"
  rm -f "$rendered"
done

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf 'assets.test.sh: PASS (Node Trail asset contract)\n'
