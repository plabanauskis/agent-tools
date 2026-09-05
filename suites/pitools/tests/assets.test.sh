#!/usr/bin/env bash
# Asset and public-doc contract for the Pi Trail port.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

readonly LIGHT_ACCENT='#4B607C'
readonly DARK_ACCENT='#6A9FCC'
readonly LIGHT_INK='#252F3D'
readonly DARK_INK='#F3F2F0'
readonly SOCIAL_BG='#0D1116'

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=1
}
need_file() { [ -f "$1" ] || fail "missing asset: $1"; }
need_text() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "$file" || fail "missing required text in $file: $text"
}
has_rendered_color() {
  local file="$1" color="$2"
  # Do not use grep -q here: under pipefail its early exit can SIGPIPE convert.
  convert -background none "$file" -resize 512x512 -depth 8 -format '%c' histogram:info:- |
    grep -i "${color#\#}" >/dev/null
}

for tool in pichat pisession pibox; do
  for asset in icon.svg icon-dark.svg logo.svg logo-dark.svg og-image.svg og-image.png; do
    need_file "tools/$tool/assets/$asset"
  done
  need_file "tools/$tool/README.md"
done
need_file README.md

# Keep public/local install, Pi state/session, exact-install, and isolation promises visible.
need_text README.md 'gh repo clone plabanauskis/agent-tools'
need_text README.md 'bash install.sh --suite=pitools'
need_text README.md 'repository is private'
need_text README.md "PITOOLS_REPO=\"file://\$PWD\""
need_text README.md 'fetches and prunes, then hard-resets'
need_text README.md 'PI_CODING_AGENT_DIR'
need_text README.md 'PI_CODING_AGENT_SESSION_DIR'
need_text README.md 'does not invent or pass a bypass flag'
need_text tools/pichat/README.md '--no-session'
need_text tools/pisession/README.md 'pi --session <file>'
need_text tools/pisession/README.md 'PI_CODING_AGENT_SESSION_DIR'
need_text tools/pisession/README.md "\$HOME/.pi/agent"
need_text tools/pibox/README.md 'never mounted'
need_text tools/pibox/README.md 'narrow the blast radius'
need_text tools/pibox/README.md '@earendil-works/pi-coding-agent'
need_text tools/pibox/README.md 'PIBOX_SHARE_DIR'
need_text tools/pibox/README.md 'explicit allowlist'
need_text tools/pibox/README.md 'no approval-bypass or sandbox-bypass option'

# Catch accidental Codex-port residue in active source/docs/assets. Tests are
# excluded because some deliberately assert forbidden strings are absent.
legacy_status=0
legacy_hits="$(rg -n -i --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!LICENSE' \
  --glob '!tests/**' \
  --glob '!tools/*/tests/**' \
  --glob '!tools/*/test/**' \
  -e 'Codex (CLI|Desktop|session|state)|CODEX_HOME|CODEX_ACCESS_TOKEN|@openai/codex' \
  -e 'dangerously-bypass-approvals-and-sandbox' \
  -e '#10A37F' .)" || legacy_status=$?
if [ "$legacy_status" -gt 1 ]; then
  fail "legacy harness audit failed (rg exit $legacy_status)"
elif [ -n "$legacy_hits" ]; then
  fail "legacy Codex runtime/brand term remains:\n$legacy_hits"
fi

if [ "$failures" -ne 0 ]; then exit 1; fi

for tool in pichat pisession pibox; do
  asset_dir="tools/$tool/assets"

  [ "$(identify -format '%wx%h' "$asset_dir/icon.svg")" = '128x128' ] ||
    fail "icon dimensions must be 128x128: $asset_dir/icon.svg"
  [ "$(identify -format '%wx%h' "$asset_dir/icon-dark.svg")" = '128x128' ] ||
    fail "dark icon dimensions must be 128x128: $asset_dir/icon-dark.svg"
  logo_size='360x160'
  [ "$tool" = pisession ] && logo_size='480x160'
  for variant in logo.svg logo-dark.svg; do
    [ "$(identify -format '%wx%h' "$asset_dir/$variant")" = "$logo_size" ] ||
      fail "wordmark dimensions must be $logo_size: $asset_dir/$variant"
  done
  [ "$(identify -format '%wx%h' "$asset_dir/og-image.svg")" = '1280x640' ] ||
    fail "social SVG must be 1280x640: $asset_dir/og-image.svg"

  for svg in "$asset_dir"/*.svg; do
    xmllint --noout "$svg" || fail "invalid SVG XML: $svg"
    rg -q 'M165\.29 165\.29' "$svg" || fail "official Pi pixel mark missing from: $svg"
    if rg -qi 'Codex|cobox|cochat|cosession|10A37F|D97757' "$svg"; then
      fail "old suite/harness branding remains in: $svg"
    fi
  done

  for variant in icon.svg logo.svg; do
    has_rendered_color "$asset_dir/$variant" "$LIGHT_ACCENT" ||
      fail "light asset lacks Pi tidal-blue accent: $asset_dir/$variant"
    has_rendered_color "$asset_dir/$variant" "$LIGHT_INK" ||
      fail "light asset lacks evening-blue ink: $asset_dir/$variant"
  done
  for variant in icon-dark.svg logo-dark.svg og-image.svg; do
    has_rendered_color "$asset_dir/$variant" "$DARK_ACCENT" ||
      fail "dark asset lacks Pi accent blue: $asset_dir/$variant"
    has_rendered_color "$asset_dir/$variant" "$DARK_INK" ||
      fail "dark asset lacks warm-white ink: $asset_dir/$variant"
  done

  for variant in icon.svg icon-dark.svg logo.svg logo-dark.svg; do
    rendered="$(mktemp "${TMPDIR:-/tmp}/pitools-asset.XXXXXX.png")"
    convert -background none "$asset_dir/$variant" -depth 8 "$rendered"
    [ "$(identify -format '%[pixel:p{0,0}]' "$rendered")" = 'srgba(0,0,0,0)' ] ||
      fail "mark must retain a transparent canvas: $asset_dir/$variant"
    rm -f "$rendered"
  done

  [ "$(identify -format '%wx%h' "$asset_dir/og-image.png")" = '1280x640' ] ||
    fail "social PNG must be 1280x640: $asset_dir/og-image.png"
  [ "$(identify -format '%[pixel:p{0,0}]' "$asset_dir/og-image.png")" = 'srgba(13,17,22,1)' ] ||
    fail "social PNG must have opaque $SOCIAL_BG background: $asset_dir/og-image.png"

  rendered="$(mktemp "${TMPDIR:-/tmp}/pitools-social.XXXXXX.png")"
  convert "$asset_dir/og-image.svg" "$rendered"
  [ "$(compare -metric AE "$asset_dir/og-image.png" "$rendered" null: 2>&1)" = '0' ] ||
    fail "social PNG must be reproducible from SVG: $asset_dir/og-image.png"
  rm -f "$rendered"
done

if [ "$failures" -ne 0 ]; then exit 1; fi
printf 'assets.test.sh: PASS (Pi Trail asset contract)\n'
