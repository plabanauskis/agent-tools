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

has_rendered_color() {
  local file="$1" color="$2"
  convert -background none "$file" -resize 512x512 -depth 8 -format '%c' histogram:info:- |
    grep -qi "${color#\#}"
}

for tool in cochat cosession cobox; do
  for asset in icon.svg icon-dark.svg logo.svg logo-dark.svg og-image.svg og-image.png; do
    need_file "tools/$tool/assets/$asset"
  done
done

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
